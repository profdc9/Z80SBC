# Z80 Single Board Computer

This is a PCB layout by Daniel Marks of Grant Searle's 9 chip CP/M computer as obtained from

http://searle.x10host.com/cpm/index.html

You need to follow his instructions on how to flash the memory and install CP/M.

http://searle.x10host.com/cpm/z80sbcFiles.zip

This design uses a 28C256 (32k X 8 EEPROM) rather than the original 27128 (16 x 8 EPROM).  JP6 needs to be set to the 16K setting, and only the first 16K of the EEPROM needs to be programmed.

I have added a 8255A peripheral interface and a SPI serial peripheral interface port.  I plan on modifying the SD card driver to use the faster hardware on this board, using the SD card loader here:

http://xepb.org/dtz/sgsbcsd.html

The SPI peripheral will hopefully allow other hardware to be easily added such as an ethernet interface (Wiznet or enc28j60) for TCP/IP, a SPI LCD for display, etc.  JP2 selects the clockspeed of the SPI, either 1/2 of 7.3278 MHz (slow clock) or 16 MHz (fast clock).
