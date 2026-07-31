sfr SBUF = 0x99;

volatile unsigned char first;
volatile unsigned char second;

void main(void)
{
    first = 0x12;
    second = first;
    second++;
    SBUF = first;
    SBUF = second;

    if (first == 0x12 && second == 0x13)
        SBUF = 0x55;
    else
        SBUF = 0xAA;

    while (1)
    {
    }
}