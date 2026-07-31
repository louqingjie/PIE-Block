sfr SBUF = 0x99;

unsigned char add8(unsigned char left, unsigned char right)
{
    return left + right;
}

unsigned int sum_to(unsigned char limit)
{
    unsigned int sum = 0;

    while (limit != 0)
    {
        sum += limit;
        limit--;
    }
    return sum;
}

void main(void)
{
    unsigned int sum;
    unsigned char value;

    value = add8(0x20, 0x0A);
    SBUF = value;
    sum = sum_to(5);
    SBUF = (unsigned char)(sum >> 8);
    SBUF = (unsigned char)sum;
    if (value == 0x2A && sum == 15)
        SBUF = 0x55;
    else
        SBUF = 0xAA;

    while (1)
    {
    }
}