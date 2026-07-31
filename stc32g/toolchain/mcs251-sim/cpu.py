"""Minimal, fail-closed MCS-251 instruction interpreter."""

from __future__ import annotations

from dataclasses import dataclass, field

from ihex import HexImage


class SimulationError(RuntimeError):
    """Base class for deterministic simulation failures."""


class IllegalInstruction(SimulationError):
    def __init__(self, address: int, opcode: int) -> None:
        super().__init__(f"unsupported opcode 0x{opcode:02X} at 0x{address:06X}")
        self.address = address
        self.opcode = opcode


class ExecutionLimitExceeded(SimulationError):
    pass


ACC = 0xE0
PSW = 0xD0
SP = 0x81
SBUF = 0x99
S2BUF = 0x9B
S3BUF = 0xAD
S4BUF = 0xFE

CY_MASK = 0x80
AC_MASK = 0x40
OV_MASK = 0x04
P_MASK = 0x01

UART_REGISTERS = {
    SBUF: 1,
    S2BUF: 2,
    S3BUF: 3,
    S4BUF: 4,
}


@dataclass(frozen=True)
class UartWrite:
    step: int
    channel: int
    value: int


@dataclass
class MCS251Cpu:
    code: dict[int, int]
    pc: int = 0
    iram: bytearray = field(default_factory=lambda: bytearray(0x10000))
    sfr: bytearray = field(default_factory=lambda: bytearray(0x100))
    registers: bytearray = field(default_factory=lambda: bytearray(16))
    uart_trace: list[UartWrite] = field(default_factory=list)
    steps: int = 0

    @classmethod
    def from_hex(cls, image: HexImage, *, reset_address: int | None = None) -> MCS251Cpu:
        if reset_address is None:
            reset_address = image.entry_point
        if reset_address is None:
            reset_address = min(image.memory)
        cpu = cls(code=dict(image.memory), pc=reset_address)
        cpu.sfr[SP] = 0x07
        return cpu

    @property
    def accumulator(self) -> int:
        return self.registers[11]

    @accumulator.setter
    def accumulator(self, value: int) -> None:
        value &= 0xFF
        self.registers[11] = value
        self.sfr[ACC] = value
        self._update_parity()

    def read_register(self, register: int) -> int:
        return self.registers[register]

    def write_register(self, register: int, value: int) -> None:
        self.registers[register] = value & 0xFF
        if register == 11:
            self.sfr[ACC] = value & 0xFF
            self._update_parity()

    def read_word_register(self, register_pair: int) -> int:
        high_register = register_pair * 2
        return (self.registers[high_register] << 8) | self.registers[high_register + 1]

    def write_word_register(self, register_pair: int, value: int) -> None:
        high_register = register_pair * 2
        self.write_register(high_register, value >> 8)
        self.write_register(high_register + 1, value)

    def read_direct(self, address: int) -> int:
        if not 0 <= address <= 0xFF:
            raise SimulationError(f"direct address out of range: 0x{address:X}")
        if address < 0x80:
            return self.iram[address]
        if address == ACC:
            return self.accumulator
        return self.sfr[address]

    def write_direct(self, address: int, value: int) -> None:
        value &= 0xFF
        if not 0 <= address <= 0xFF:
            raise SimulationError(f"direct address out of range: 0x{address:X}")
        if address < 0x80:
            self.iram[address] = value
            return
        if address == ACC:
            self.accumulator = value
            return
        self.sfr[address] = value
        channel = UART_REGISTERS.get(address)
        if channel is not None:
            self.uart_trace.append(UartWrite(self.steps, channel, value))

    def step(self) -> None:
        instruction_address = self.pc
        opcode = self._fetch()

        if opcode == 0x00:  # NOP
            pass
        elif opcode == 0x02:  # LJMP addr16
            high = self._fetch()
            low = self._fetch()
            self.pc = (self.pc & 0xFF0000) | (high << 8) | low
        elif opcode == 0x12:  # LCALL addr16
            high = self._fetch()
            low = self._fetch()
            return_address = self.pc
            self._push(return_address & 0xFF)
            self._push((return_address >> 8) & 0xFF)
            self.pc = (self.pc & 0xFF0000) | (high << 8) | low
        elif opcode == 0x22:  # RET
            high = self._pop()
            low = self._pop()
            self.pc = (self.pc & 0xFF0000) | (high << 8) | low
        elif opcode == 0x04:  # INC A
            self.accumulator = self.accumulator + 1
        elif opcode == 0x05:  # INC direct
            address = self._fetch()
            self.write_direct(address, self.read_direct(address) + 1)
        elif opcode == 0x0A:  # MOVZ WRn,Rm
            operands = self._fetch()
            destination_pair = operands >> 4
            source_register = operands & 0x0F
            self.write_word_register(destination_pair, self.read_register(source_register))
        elif opcode == 0x1B:  # DEC Rn,#1 (calibrated form)
            operands = self._fetch()
            if operands & 0x0F:
                raise IllegalInstruction(instruction_address, opcode)
            register = operands >> 4
            self.write_register(register, self.read_register(register) - 1)
        elif opcode == 0x24:  # ADD A,#data
            self._add_to_accumulator(self._fetch())
        elif opcode == 0x2D:  # ADD WRn,WRm
            operands = self._fetch()
            destination_pair = operands >> 4
            source_pair = operands & 0x0F
            result = self.read_word_register(destination_pair) + self.read_word_register(source_pair)
            self.write_word_register(destination_pair, result)
        elif opcode == 0x60:  # JZ rel
            displacement = self._signed_byte(self._fetch())
            if self.accumulator == 0:
                self.pc = (self.pc + displacement) & 0xFFFFFF
        elif opcode == 0x70:  # JNZ rel
            displacement = self._signed_byte(self._fetch())
            if self.accumulator != 0:
                self.pc = (self.pc + displacement) & 0xFFFFFF
        elif opcode == 0x6D:  # XRL WRn,WRm
            operands = self._fetch()
            destination_pair = operands >> 4
            source_pair = operands & 0x0F
            value = self.read_word_register(destination_pair) ^ self.read_word_register(source_pair)
            self.write_word_register(destination_pair, value)
        elif opcode == 0x74:  # MOV A,#data
            self.accumulator = self._fetch()
        elif opcode == 0x75:  # MOV direct,#data
            address = self._fetch()
            self.write_direct(address, self._fetch())
        elif opcode == 0x78:  # JNE rel
            displacement = self._signed_byte(self._fetch())
            if not self._zero_flag():
                self.pc = (self.pc + displacement) & 0xFFFFFF
        elif opcode == 0x7A:  # MOV direct,Rn
            operands = self._fetch()
            if operands & 0x0F != 1:
                raise IllegalInstruction(instruction_address, opcode)
            source_register = operands >> 4
            self.write_direct(self._fetch(), self.read_register(source_register))
        elif opcode == 0x7C:  # MOV Rn,Rm
            operands = self._fetch()
            self.write_register(operands >> 4, self.read_register(operands & 0x0F))
        elif opcode == 0x7E:  # MOV Rn,#data
            operands = self._fetch()
            if operands & 0x0F:
                raise IllegalInstruction(instruction_address, opcode)
            self.write_register(operands >> 4, self._fetch())
        elif opcode == 0x80:  # SJMP rel
            displacement = self._signed_byte(self._fetch())
            self.pc = (self.pc + displacement) & 0xFFFFFF
        elif opcode == 0x85:  # MOV direct,direct (source first in encoding)
            source = self._fetch()
            destination = self._fetch()
            self.write_direct(destination, self.read_direct(source))
        elif opcode == 0xB4:  # CJNE A,#data,rel
            immediate = self._fetch()
            displacement = self._signed_byte(self._fetch())
            left = self.accumulator
            self._set_compare_flags(left, immediate, bits=8)
            if left != immediate:
                self.pc = (self.pc + displacement) & 0xFFFFFF
        elif opcode == 0xE4:  # CLR A
            self.accumulator = 0
        elif opcode == 0xE5:  # MOV A,direct
            self.accumulator = self.read_direct(self._fetch())
        elif opcode == 0xF5:  # MOV direct,A
            self.write_direct(self._fetch(), self.accumulator)
        elif opcode == 0xBE:  # CMP Rn/WRn,#data
            operands = self._fetch()
            destination = operands >> 4
            mode = operands & 0x0F
            if mode == 0:
                left = self.read_register(destination)
                right = self._fetch()
            elif mode == 4:
                left = self.read_word_register(destination)
                right = (self._fetch() << 8) | self._fetch()
            else:
                raise IllegalInstruction(instruction_address, opcode)
            self._set_compare_flags(left, right, bits=16 if mode == 4 else 8)
        elif opcode == 0xA5:  # Extended instruction prefix
            extension = self._fetch()
            if extension != 0xBD:
                raise IllegalInstruction(instruction_address, opcode)
            immediate = self._fetch()
            displacement = self._signed_byte(self._fetch())
            register = 5
            left = self.read_register(register)
            self._set_compare_flags(left, immediate, bits=8)
            if left != immediate:
                self.pc = (self.pc + displacement) & 0xFFFFFF
        else:
            raise IllegalInstruction(instruction_address, opcode)

        self.steps += 1

    def run(self, *, max_steps: int, stop_pc: int | None = None) -> None:
        while self.steps < max_steps:
            if stop_pc is not None and self.pc == stop_pc:
                return
            self.step()
        if stop_pc is not None and self.pc == stop_pc:
            return
        raise ExecutionLimitExceeded(f"execution exceeded {max_steps} instructions")

    def _fetch(self) -> int:
        try:
            value = self.code[self.pc]
        except KeyError as exc:
            raise SimulationError(f"execute from unmapped code address 0x{self.pc:06X}") from exc
        self.pc = (self.pc + 1) & 0xFFFFFF
        return value

    def _push(self, value: int) -> None:
        stack_pointer = (self.sfr[SP] + 1) & 0xFF
        self.sfr[SP] = stack_pointer
        self.iram[stack_pointer] = value & 0xFF

    def _pop(self) -> int:
        stack_pointer = self.sfr[SP]
        value = self.iram[stack_pointer]
        self.sfr[SP] = (stack_pointer - 1) & 0xFF
        return value

    def _add_to_accumulator(self, operand: int) -> None:
        left = self.accumulator
        total = left + operand
        result = total & 0xFF
        psw = self.sfr[PSW] & ~(CY_MASK | AC_MASK | OV_MASK)
        if total > 0xFF:
            psw |= CY_MASK
        if (left & 0x0F) + (operand & 0x0F) > 0x0F:
            psw |= AC_MASK
        if (~(left ^ operand) & (left ^ result) & 0x80) != 0:
            psw |= OV_MASK
        self.sfr[PSW] = psw
        self.accumulator = result

    def _update_parity(self) -> None:
        parity = self.accumulator.bit_count() & 1
        self.sfr[PSW] = (self.sfr[PSW] & ~P_MASK) | parity

    def _set_compare_flags(self, left: int, right: int, *, bits: int) -> None:
        zero_mask = 0x02
        carry = left < right
        equal = left == right
        self.sfr[PSW] = (self.sfr[PSW] & ~CY_MASK) | (CY_MASK if carry else 0)
        self.sfr[0xD1] = (self.sfr[0xD1] & ~zero_mask) | (zero_mask if equal else 0)

    def _zero_flag(self) -> bool:
        return bool(self.sfr[0xD1] & 0x02)

    @staticmethod
    def _signed_byte(value: int) -> int:
        return value - 0x100 if value & 0x80 else value