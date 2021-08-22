
;------------------------------------------------------------------------------
;
; Z80 CP/M Video Demonstration
; by Daniel Marks

CTL8255 EQU     $1B
PTB8255 EQU     $19
SPIDPT  EQU     $20

STRT    ORG     $100
       
        JP      START

; Video Frame Buffer Defines

VIDFR   EQU     $2000       ; Location of frame buffer
VIDWDTH EQU     24          ; Number of bytes across in frame buffer (min 24)
VIDLN   EQU     246/2       ; Number of scan lines (246 for full, 246/2 for double lines)
VBLLN   EQU     16          ; Number of vertical blanking lines
VIDBYT  EQU     VIDWDTH*VIDLN   ; Number of bytes in frame bufer

DECFR   DB      0           ; The number of frames before leaving the video output loop
DECTL   DB      1           ; This is zero if stay in loop, or one if leave loop
                            ; always change DECFR before DECTL in interrupt
                            ; these are used to terminate the loop
CURCOL  DW      0           ; current offset for scrolling horizontally in framebuffer
FRAMEST DW      0           ; scratch for saving current framebuffer origin

; PS/2 Keyboard Defines

PS2STAT DB      0           ; Current state of PS2 keyboard driver in interrupt
PS2CC   DB      0           ; Current PS2 code being assembled by driver

PS2BUF  DS      8           ; Buffer size must be power of two
PS2BUFE EQU     $                     
PS2BITM EQU     (PS2BUFE-PS2BUF-1)   ; Bit mask for driver

PS2BUFI DB      0           ; Character being read out of FIFO buffer
PS2BUFO DB      0           ; Character beign written into FIFO buffer

; SIO control that we use for using the SIO interrupt for PS/2 keyboard interrupt

SIOA_D  EQU     $00
SIOA_C  EQU     $02
SIOB_D  EQU     $01
SIOB_C  EQU     $03

; Stuff for COM CP/M housekeeping

OLDSTK  DW      0            ; old stack pointer
NEWSTK  DS      64           ; new stack pointer
STOPSTK EQU     $-1
BDOS    EQU     5            ; CP/M BDOS call
SIOINTA EQU     $FFE0        ; Location of SIO interrupt pointer

MSGSTR  DB      13,10,"START PROGRAM",13,10,0
VIDMSG  DB      13,10,"CLEARED VIDEO",13,10,0

START   LD      HL,0
        ADD     HL,SP
        LD      (OLDSTK),HL     ; Save stack ptr
        LD      HL,STOPSTK      ; Use new stack
        LD      SP,HL
        LD      HL,MSGSTR
        CALL    OUTSTR          ; Display message
        CALL    INITVID         ; Initialize frame buffer
        CALL    INITPS2         ; Initialize PS/2 routine
        CALL    PS2INTS         ; Initialize interrupt and redirect
                                ; from CP/M BIOS
        LD      HL,VIDMSG       ; Say we initialized frame buffer
        CALL    OUTSTR
               
NL      CALL    GETPS2C
        OR      A
        JR      Z,NL2

        PUSH    AF
        LD      E,A         ; otherwise output using BDOS
        LD      C,2
        CALL    BDOS
        POP     AF
        JR      NL

NL2     LD      A,1             ; Set up to display 60 frames
        LD      (DECFR),A
        LD      A,60
        LD      (DECTL),A
        
        CALL    VIDEOF2         ; Call display function

        LD      A,(CURCOL)      ; Move scroll register to
        INC     A               ; pan display horizontally
        AND     $0f
        LD      (CURCOL),A

        LD      C,6        ; see if there is a key ready
        LD      E,$FF
        CALL    BDOS
        OR      A
        JP      Z,NL       ; if not, keep scrolling

        CALL    PS2INTD   ; Restore interrupt to CP/M BIOS

        LD      HL,(OLDSTK)    ; restore the stack
        LD      SP,HL          ; and leave
        RET
 
;  Outputs a string at HL

OUTSTR  PUSH    AF 
        PUSH    BC
        PUSH    DE
OUTL    LD      A,(HL)      ; Load a character
        OR      A           ; if zero quit
        JR      Z,OUTEX    
        LD      E,A         ; otherwise output using BDOS
        LD      C,2
        PUSH    HL
        CALL    BDOS
        POP     HL
        INC     HL          ; go to next character
        JP      OUTL
OUTEX   POP     DE
        POP     BC
        POP     AF
        RET
        
;  Initialize video frame buffer.  Fills it with a pattern
;  We force the SD card select lines high so that we don't accidentally
;  confuse the SD card with video data ! 
        
INITVID LD      A,$92           ; Configure port B as input, C as output
        OUT     (CTL8255),A
        LD      A,$3
        OUT     (CTL8255),A      ; Force SD card select lines high! 
        LD      A,$1
        OUT     (CTL8255),A
        LD      BC,VIDFR
        LD      HL,VIDBYT       ; Start at the top of buffer
CLRV    LD      A,C             ; Fill the buffer with a pattern
        AND     $7F
        ADD     A,B
        LD      (BC),A
        LD      A,$0
        INC     BC
        DEC     HL
        OR      H
        OR      L
        JP      NZ,CLRV         ; Keep going until the end
        RET                
        
; This is the main video output routine.  All of the timings
; here are cycle dependent!  Don't change the instructions
; without knowing how the timing is changing...        
;
; Yes it is a hack, but getting it to have exactly 15.752 kHz
; horizontal scan rate ain't easy..
;
; There are VIDLN regular scan lines, and then VBLLN 
; vertical blanking lines with inverted sync pulses.
; all of the pulses must occur at 15.752 kHz (or as close as we
; can get it) or the display will not lock onto the scan
; lines.
;
VIDEOFR LD      C,SPIDPT                ; output to shift register
        LD      DE,(CURCOL)             ; calculate the beginning of the frame buffer
        LD      HL,VIDFR-(VIDWDTH-24)   
        ADD     HL,DE                   ; add offset for current shift window
        LD      (FRAMEST),HL            ; start at current frame
        LD      DE,VIDWDTH-24           
        LD      B,VIDLN         ; Load the number of visible scan lines
LINEST  LD      A,14            ; Send a brief sync pulse (about 4.5 us)
        OUT     (CTL8255),A
        ADD     HL,DE           ; This add is here to lengthen the sync pulse
        LD      A,15            ; This is not an INC because we need 7 t-states
        OUT     (CTL8255),A
        LD      A,B             ; Save B register
        
        NOP                     ; Delay between sync and scan line information
        NOP
        NOP
        NOP
        OUTI                    ; Stream 24 bytes of data out to the register
        OUTI                    ; (192 pixels)
        OUTI
        OUTI
        
        OUTI
        OUTI
        OUTI 
        OUTI
        OUTI

        OUTI
        OUTI
        OUTI
        OUTI
        OUTI

        OUTI
        OUTI
        OUTI
        OUTI
        OUTI

        OUTI
        OUTI
        OUTI
        OUTI
        OUTI

        LD      B,A             ; Load B back
        DJNZ    LINEST          ; Keep going until all scan lines done
        LD      B,0             ; Delay so that inverted sync in vertical blanking
        LD      B,0             
        LD      B,0
        
VBLT    LD      B,VBLLN-1       ; Vertical blanking lines
        JP      VBLSCN
VBLALT  LD      A,VBLLN-1       ; Alternate loop path with the same number of t-states
        JP      VBLSCN
VBLSCN  LD      A,B
        LD      B,28
VWAIT   DJNZ    VWAIT           ; Wait 28 X 13 t-states approx
        NOP                     ; More waiting to line up VBL sync with
        NOP                     ; regular scan line SYNC
        LD      B,A
        LD      A,15            ; Send an inverted sync pulse (4.5 us)
        OUT     (CTL8255),A      
        NOP
        NOP
        NOP
        NOP
        NOP
        LD      A,14           
        OUT     (CTL8255),A
        DJNZ    VBLALT

        LD      A,(DECFR)       ; See if we have displayed the number of frames
        LD      B,A
        LD      A,(DECTL)       
        SUB     B
        RET     Z               ; If frames decrement to zero, leave loop
        LD      (DECTL),A
        LD      B,23            ; This is just waiting
        NOP
        NOP 
        LD      B,23            ; We wait for 23 X 13 t-states
VWAIT2  DJNZ    VWAIT2          ; to get the last sync pulse to line up
        LD      HL,(FRAMEST)
        LD      B,VIDLN

        LD      A,15            ; Send a the last sync pulse in frame (4.5 us)
        OUT     (CTL8255),A
        NOP
        NOP
        NOP
        NOP
        NOP
        LD      A,14     
        OUT     (CTL8255),A        
        JP      LINEST         ; Send another frame!



; This is a modified routine to double the scan lines
; to save memory
;
VIDEOF2 LD      C,SPIDPT                ; output to shift register
        LD      DE,(CURCOL)             ; calculate the beginning of the frame buffer
        LD      HL,VIDFR-(VIDWDTH-24)   
        ADD     HL,DE                   ; add offset for current shift window
        LD      (FRAMEST),HL            ; start at current frame
        LD      DE,VIDWDTH-24           
        LD      B,VIDLN         ; Load the number of visible scan lines
LINEST2 LD      A,14            ; Send a brief sync pulse (about 4.5 us) 
        OUT     (CTL8255),A      ; for first scan line copy
        ADD     HL,DE           ; Advance to the beginning of line
        LD      A,15            ; This is not an INC because we need 7 t-states
        OUT     (CTL8255),A
        LD      A,B             ; Save B register
        
        DEC     DE
        LD      DE,-25          ; Delay between sync and scan line information    
                                ; this is -25 because we INC DE to waste time
                                ; so that DE is -24 afterwards
        OUTI                    ; Stream 24 bytes of data out to the register
        OUTI                    ; (192 pixels)
        OUTI                    ; 16 t-states per OUTI
        OUTI
        
        OUTI
        OUTI
        OUTI 
        OUTI
        OUTI

        OUTI
        OUTI
        OUTI
        OUTI
        OUTI

        OUTI
        OUTI
        OUTI
        OUTI
        OUTI

        OUTI
        OUTI
        OUTI
        OUTI
        OUTI

        PUSH    AF              ; Save A and waste 11 t-states
        INC     DE              ; INC DE to waste 6 t-states (-25 to -24)

        LD      A,14            ; Send a brief sync pulse (about 4.5 us)
        OUT     (CTL8255),A      ; For second scan line copy
        ADD     HL,DE           ; Return HL to beginning of line to send
        LD      A,15            ; This is not an INC because we need 7 t-states
        OUT     (CTL8255),A

        POP     AF              ; Pop AF to restore (11 t-states)
        LD      DE,VIDWDTH-24   ; Put DE back for next frame (10 t-states)
        OUTI                    ; Stream 24 bytes of data out to the register
        OUTI                    ; (192 pixels)
        OUTI                    ; 16 t-states per OUTI
        OUTI
        
        OUTI
        OUTI
        OUTI 
        OUTI
        OUTI

        OUTI
        OUTI
        OUTI
        OUTI
        OUTI

        OUTI
        OUTI
        OUTI
        OUTI
        OUTI

        OUTI
        OUTI
        OUTI
        OUTI
        OUTI

        LD      B,A             ; Load B back
        DJNZ    LINEST2         ; Keep going until all scan lines done
        LD      B,0             ; Delay so that inverted sync in vertical blanking
        LD      B,0             
        LD      B,0
        
VBLT2   LD      B,VBLLN-1       ; Vertical blanking lines
        JP      VBLSCN2
VBLALT2 LD      A,VBLLN-1       ; Alternate loop path with the same number of t-states
        JP      VBLSCN2
VBLSCN2 LD      A,B
        LD      B,28
VWAITD2 DJNZ    VWAITD2         ; Wait 28 X 13 t-states approx
        NOP                     ; More waiting to line up VBL sync with
        NOP                     ; regular scan line SYNC
        LD      B,A
        LD      A,15            ; Send an inverted sync pulse (4.5 us)
        OUT     (CTL8255),A      
        NOP
        NOP
        NOP
        NOP
        NOP
        LD      A,14           
        OUT     (CTL8255),A
        DJNZ    VBLALT2

        LD      A,(DECFR)       ; See if we have displayed the number of frames
        LD      B,A
        LD      A,(DECTL)       
        SUB     B
        RET     Z               ; If frames decrement to zero, leave loop
        LD      (DECTL),A
        LD      B,23            ; This is just waiting
        NOP
        NOP 
        LD      B,23            ; We wait for 23 X 13 t-states
VWAITE2 DJNZ    VWAITE2         ; to get the last sync pulse to line up
        LD      HL,(FRAMEST)
        LD      B,VIDLN

        LD      A,15            ; Send a the last sync pulse in frame (4.5 us)
        OUT     (CTL8255),A
        NOP
        NOP
        NOP
        NOP
        NOP
        LD      A,14     
        OUT     (CTL8255),A        
        JP      LINEST2        ; Send another frame!

; Interrupt routine for SIO that is used to clock in PS/2
; bits.  The status line change interrupt on SIO is used to detect
; when the SYNCA/RIA pin transitions low, and the clock pin of the PS/2
; keyboard is wired to this.

NEWINTR DI
        PUSH    AF
        LD      A,$10         ; Clear the status condition 
        OUT     (SIOA_C),A    
        IN      A,(SIOA_C)    ; Read the SYNC/RIA pin
        BIT     4,A           ; If not low, the clock is not low
        JR      Z,NCONT       ; and we just go to SIO

        LD      A,(PS2STAT)   ; Dispatch depending on current stae
        OR      A
        JR      Z,PS2STB      ; State 0 means first bit being read
        CP      $9
        JR      Z,PS2PAR      ; State 9 means parity bit being read
      
                              ; Otherwise we are clocking in a data bit
PS2CLK  IN      A,(PTB8255)   ; Clock in a bit
        RRCA     
        LD      A,(PS2CC)     ; Shift it into current byte register
        RR      A
        LD      (PS2CC),A 
        JR      PS2INCS       ; Clock to next state
        
PS2PAR  PUSH    HL            ; If we are clocking in parity bit
        LD      HL,(PS2CC)    ; Load current byte
        LD      H,8           ; Load number of bits
        XOR     A
PS2CLC  RRC     L             ; Add together # of 1s to get parity
        ADC     A,0
        DEC     H
        JR      NZ,PS2CLC     ; Loop until all 8 bits are added
        LD      H,A
        IN      A,(PTB8255)   ; Get parity bit from port
        ADD     A,H           ; Add to compare to parity bit
        AND     $1            ; If result is non zero, they dont match
        JR      Z,PS2ENDP

                              ; Otherwise we stuff FIFO buffer with code
        LD      A,(PS2BUFI)   
        LD      L,A
        LD      A,(PS2BUFO)   ; Get output head of buffer
        INC     A
        AND     PS2BITM       ; wrap to beginning if appropriate
        CP      L             ; if we fit the read ptr then
        JR      Z,PS2ENDP     ; Buffer is full, can't add more

        LD      (PS2BUFO),A    ; Store new pointer value
        LD      L,A            ; Calculate pointer offset into buffer
        LD      A,PS2BUF & $FF ; by adding offset to pointer head
        ADD     A,L            ; using painful 16 bit addition
        LD      L,A
        LD      A,PS2BUF >> 8
        ADC     A,0
        LD      H,A
        LD      A,(PS2CC)     ; Store bytecode into buffer
        LD      (HL),A
        XOR     A
        
        LD      (DECTL),A     ; Clear the frame decrement registers to exit loop
        LD      (DECFR),A
        
PS2ENDP POP     HL
        XOR     A        
        JR      PS2RSTS
      
PS2STB  IN      A,(PTB8255)   ; Don't advance to next state unless 
        RRCA                  ; bit is zero
        JR      C,PS2END       
        
PS2INCS LD      A,(PS2STAT)
        INC     A
PS2RSTS LD      (PS2STAT),A
PS2END  POP     AF
        EI
        RETI
NCONT   POP     AF
NEWINTJ JP      $0000  
SAVEADR EQU     NEWINTJ+1      ; ADDRESS OF OLD INTERRUPT HANDLER
                               ; is in JP instruction


; Set up SIO for interrupting on the SYNCA/RIA signal
; Because we're in CP/M, we also have to save the old SIO interrupt
; address and call it.  We wouldn't have to do this necessarily
;  in another operating system

PS2INTS DI                      ; Disable interrupts       

        LD      A,$11           ; Enable interrupts on status change condition
        OUT     (SIOA_C),A      ; as well as receive interrupts
        LD      A,$19
        OUT     (SIOA_C),A
        
        LD      HL,(SIOINTA)    ; Copy address to scratch area
        LD      (SAVEADR),HL
        LD      HL,NEWINTR      ; Place out new interrupt handler there
        LD      (SIOINTA),HL
        EI
        RET


; Restore the interrupt handler to the old SIO interrupt routine.
; and turn off the interrupts on SYNC/RIA signal (just interrupt
; on input character).

PS2INTD DI      
        LD      HL,(SAVEADR)    ; Restore address of interrupt handler
        LD      (SIOINTA),HL

        LD      A,$11           ; Disable interrupts on status change condition
        OUT     (SIOA_C),A      ; keep receive interrupts
        LD      A,$18
        OUT     (SIOA_C),A
        EI
        RET

; Initialize PS2 driver.  This repeats the initialization of 8255 for video
; but also resets the state variables for PS/2 driver

INITPS2 LD      A,$92           ; Configure port B as input, C as output
        OUT     (CTL8255),A
        LD      A,$3
        OUT     (CTL8255),A     ; Force SD card select lines high! 
        LD      A,$1
        OUT     (CTL8255),A
        XOR     A
        LD      (PS2STAT),A     ; Reset state variables of driver
        LD      (PS2BUFI),A
        LD      (PS2BUFO),A
        RET

; Get a key from PS/2 FIFO fubber

GETPS2C PUSH    HL
        LD      A,(PS2BUFO)   
        LD      L,A
        LD      A,(PS2BUFI)   ; Get input pointer
        CP      L             ; If it matches output pointer
        JR      NZ,GETKY      ; Buffer is not empty, get character
        POP     HL
        XOR     A             ; Return 0 for no code available
        RET
        
GETKY   INC     A               ; advance to next location where character is
        AND     PS2BITM         ; wrap to beginning if necessary
        LD      (PS2BUFI),A     ; Store new pointer value
        LD      L,A             ; Calculate pointer offset into buffer
        LD      A,PS2BUF & $FF  ; using 16 bit addition
        ADD     A,L
        LD      L,A
        LD      A,PS2BUF >> 8
        ADC     A,0
        LD      H,A
        LD      A,(HL)          ; Load the code
        POP     HL
        RET
