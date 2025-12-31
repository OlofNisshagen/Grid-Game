	; --- lab4spel.asm
	;Skrivet av Karl Nord och Olof Nisshagen, 2025-12-17

	.equ	VMEM_SZ     = 5		; #rows on display
	.equ	AD_CHAN_X   = 0		; ADC0=PA0, PORTA bit 0 X-led
	.equ	AD_CHAN_Y   = 1		; ADC1=PA1, PORTA bit 1 Y-led
	.equ	GAME_SPEED  = 70	; inter-run delay (millisecs)
	.equ	PRESCALE    = 3		; AD-prescaler value
	.equ	BEEP_PITCH  = 60	; Victory beep pitch
	.equ	BEEP_LENGTH = 255	; Victory beep length
	
	; ---------------------------------------
	; --- Memory layout in SRAM
	; ---------------------------------------

	.dseg
	.org	SRAM_START
POSX:	.byte	1	; Own position
POSY:	.byte 	1
TPOSX:	.byte	1	; Target position
TPOSY:	.byte	1
LINE:	.byte	1	; Current line	
VMEM:	.byte	VMEM_SZ ; Video MEMory
SEED:	.byte	1	; Seed for Random

	; ---------------------------------------
	; --- Macros for inc/dec-rementing
	; --- a byte in SRAM
	; ---------------------------------------

	.macro INCSRAM	; inc byte in SRAM
		lds	r16,@0
		inc	r16
		sts	@0,r16
	.endmacro

	.macro DECSRAM	; dec byte in SRAM
		lds	r16,@0
		dec	r16
		sts	@0,r16
	.endmacro

	; ---------------------------------------
	; --- Code
	.cseg
	.org 	$0
	jmp	START
	.org	INT0addr
	jmp	MUX

START:
	ldi		r16, LOW(RAMEND)	;Ladda stack-pekaren
	out		SPL, r16
	ldi		r16, HIGH(RAMEND)
	out		SPH, r16

	call	HW_INIT				;Initiera hårdvara
	call	WARM				

	; ---------------------------------------
	; --- Game-loop
	; ---------------------------------------

GAME:
	call	JOYSTICK
	cli
	call	ERASE_VMEM			;Clear i-flagga medans erase-vmem och update, sedan sätt på igen
	call	UPDATE
	sei
	call	CHECK_HIT
	call	DELAY 
	jmp GAME

CHECK_HIT:
	push r18
	push r19

	lds r18, POSX				;Laddar in spelare och targets x pos
	lds r19, TPOSX
	cpse r18, r19				;Jämför, ifall samma gå vidare, annars avsluta
	rjmp CHECK_EXIT

	lds r18, POSY				;Laddar in spelare och targets y pos
	lds r19, TPOSY
	cpse r18, r19				;Jämför, ifall samma starta om spelet, annars avsluta
	rjmp CHECK_EXIT				
	call WARM					;Starta om
CHECK_EXIT:
	pop r18
	pop r19
	ret
	
	; -------------------------
	; --- Multiplex display ---
	; -------------------------

MUX:	
MUX_START:
	push r16
	ldi r16, SREG		;Sparar flaggor
	push r16
	push r17
	push XH
	push XL

	out PORTB, r2		;Clear porter/display


LINE_CHECK:				;Kollar ifall line är lika med $04, alltså ifall linen är högst upp
	lds r21, LINE
	cpi r21, $04
	brlo LINE_INCREASE	;Ifall line =/ $04, increase
	clr r21				;Ifall line = $04, clear
	rjmp MUX_CONTINUE
LINE_INCREASE:
	inc r21	

MUX_CONTINUE:
	call INCREASE_SEED	


	add XL, r21			;Sätt pekare till aktuell vmem-line
	adc XH, r2
	ld r16, X
	mov r17, r21		;Skickar värdet till r17 för att shiftas (A2-A4)
	lsl r17
	lsl r17
	out PORTB, r16		;Skicka ut till display
	out PORTA, r17

MUX_EXIT:
	sts LINE, r21
	pop XL
	pop XH
	pop r17
	pop r16
	out SREG, r16
	pop r16
	reti

INCREASE_SEED:
	push r16			
	lds r16, SEED		
	inc r16				;Increase seed-värde varje mux-cycle
	cpi r16, 25			;Ifall seed är 25, clear
	brlo SEED_EXIT
	clr r16

SEED_EXIT:
	sts SEED, r16		;Ladda in i SEED igen
	pop r16
	ret 

	; ---------------------------------------
	; --- WARM start. Set up a new game
	; ---------------------------------------

WARM:
	push r18
	push r19

	ldi		r18, $00	;Bestäm player start-position
	ldi		r19, $02
	sts		POSX, r18	;Sparar POS
	sts		POSY, r19
	
	cli
	push r2
	push r2
	call	RANDOM		;RANDOM returns x, y på en 5x5 grid
	pop r18
	pop r19
	sei

	sts	TPOSX, r18	;Sparar TPOS
	sts	TPOSY, r19

	call	BEEP		;Beep i början av varje nytt spel

	pop r19
	pop r18
	ret
		
JOYSTICK: 
	push r19
	push r16 
		
	ldi r16, AD_CHAN_X	;sätter kanal till noll för att kolla x led 
	lds r19, POSX    
	call CHECK    
	sts POSX, r19

	ldi r16, AD_CHAN_Y	;sätter kanal till noll för att kolla y led 
	lds r19, POSY
	call CHECK 
	sts POSY, r19

	call LIMITS			;Kollar gränser för spelplanen

	pop r16 
	pop r19
	ret
CHECK: 
	push r18
	push r17

	call CONVERT ;starta AD convertering 
	ldi r18, 3   ;laddar register med 3 
	cpse r17, r18  ; kollar om höga delen av omvandlingen är 11 , ifall sant öka POS annars gå vidare
	rjmp CHECK_ZERO
	rjmp CHECK_POS
CHECK_POS: 
	inc r19 
	rjmp JOYSTICK_END
CHECK_ZERO: 
	cpse r17, r2  ;kollar om får noll. om noll sänk (gå vänster/gå ner)
	rjmp JOYSTICK_END
	dec r19 
JOYSTICK_END: 
	pop r17
	pop r18
	ret

CONVERT:
	out ADMUX, r16		;välj kanal 0 =  x y =1
	sbi ADCSRA, ADSC
WAIT:
	sbic ADCSRA, ADSC   ;väntar till konvetering klar innan man går vidare 
	rjmp WAIT
	in r17, ADCH
	ret

	; ---------------------------------------
	; --- Player limits
	; ---------------------------------------

LIMITS: 
	lds		r16,POSX	; variable
	ldi		r17,7		; upper limit+1
	call	POS_LIM		; actual work
	sts		POSX,r16

	lds		r16,POSY	; variable
	ldi		r17,5		; upper limit+1
	call	POS_LIM		; actual work
	sts		POSY,r16
	ret

POS_LIM:
	ori		r16,0		; negative?
	brmi	POS_LESS	; POSX neg => add 1
	cp		r16,r17		; past edge
	brne	POS_OK
	subi	r16,2
POS_LESS:
	inc		r16	
POS_OK:
	ret

	; ---------------------------------------
	; --- UPDATE VMEM
	; --- with POSX/Y, TPOSX/Y
	; --- Uses r16, r17
	; ---------------------------------------

UPDATE:	
	clr		ZH 
	ldi		ZL,LOW(POSX)
	call 	SETPOS

	clr		ZH
	ldi		ZL,LOW(TPOSX)
	call	SETPOS
	ret
	; --- SETPOS Set bit pattern of r16 into *Z
	; --- Uses r16, r17
	; --- 1st call Z points to POSX at entry and POSY at exit
	; --- 2nd call Z points to TPOSX at entry and TPOSY at exit
SETPOS:
	ld		r17,Z+  	; r17=POSX
	call	SETBIT		; r16=bitpattern for VMEM+POSY
	ld		r17,Z		; r17=POSY Z to POSY
	ldi		ZL,LOW(VMEM)
	add		ZL,r17		; *(VMEM+T/POSY) ZL=VMEM+0..4
	ld		r17,Z		; current line in VMEM
	or		r17,r16		; OR on place
	st		Z,r17		; put back into VMEM
	ret
	; --- SETBIT Set bit r17 on r16
	; --- Uses r16, r17
SETBIT:
	ldi	r16,$01		; bit to shift
SETBIT_LOOP:
	dec 	r17			
	brmi 	SETBIT_END	; til done
	lsl 	r16		; shift
	jmp 	SETBIT_LOOP
SETBIT_END:
	ret

	; ---------------------------------------
	; --- Hardware init
	; --- Uses r16
	; ---------------------------------------

HW_INIT:
	clr r2		;Nollställ r2 (nollregistret)
	sts LINE, r2		
	call OUTPUTS
	call ADC8
	call BREAK_INIT 
	call ERASE_VMEM
	call SET_POINTERS
	ret

OUTPUTS:
	push r16	;Initiera outputs
	ldi r16, $FC	;Ut i "alla" portar förutom A0, A1
	out DDRA, r16
	ldi r16, $FF	;Ut i "alla" portar
	out DDRB, r16
	pop r16
	ret
	
ADC8:   ;konfigurerar AD omvandlaren 
	ldi r16, (0 << ADLAR)	;ingrn vänster justering 
	out ADMUX, r16
	ldi r16, (1 << ADEN)  ;aktiverar Omvandlaren 
	out ADCSRA, r16
	ret

BREAK_INIT:		;Initiera avbrotten
	ldi r16, (1 << INT0)	;Avbrott noll
	out GICR, r16
	ldi r16, (1 << ISC01) | (0 << ISC00) 		;stigande och fallande flank
	out MCUCR, r16
	reti

SET_POINTERS:
	ldi XH, HIGH(VMEM)	;X pekar på VMEM
	ldi XL, LOW(VMEM)
	ret

	; ---------------------------------------
	; --- Random
	; --- x = SEED mod 5
	; --- y = floor(SEED / 5)
	; ---------------------------------------

RANDOM:					
	in r16, SPH
	mov ZH, r16
	in r16, SPL
	mov ZL, r16

	push r16		

	lds r16, SEED		;ladda r16 med SEED
	clr r19				;nollställ r19, som kommer representera y-värdet
RANDOM_LOOP:
	cpi r16, $05		;kollar ifall värdet är mindre än 5 med brlo
	brlo RANDOM_END
	subi r16, $05		;ifall den är mindre än 5 substituerar den 5 från r16 och ökar y med 1
	inc r19				
	rjmp RANDOM_LOOP
RANDOM_END:				;När r16 är mindre än 5 vet vi att vi nåt rätt rad i y, alltså r19
	mov r18, r16		;Restvärdet i r16 representerar x och flyttas över till r18 för god praxis i WARM
	inc	r18			;Flytta två steg till höger på displayen
	inc	r18
	
	pop r16

	STD Z+3, r18
	STD Z+4, r19

	ret

ERASE_VMEM:				;Nollställer VMEM
	sts VMEM+0, r2
	sts VMEM+1, r2
	sts VMEM+2, r2
	sts VMEM+3, r2
	sts VMEM+4, r2
	ret

DELAY:					;Delay i varje spelcycle
	push r23
	push r24
	ldi r24, 255
DELAY_OUTER:
	ldi r23, GAME_SPEED
DELAY_INNER:
	dec r23
	brne DELAY_INNER
	dec r24
	brne DELAY_OUTER
	pop r24
	pop r23
	ret

BEEP:					;Beepfunktion
	cli
	push r20
	push r18
	push r17

	ldi r17, BEEP_LENGTH
BEEP_LOOP:
	ldi r20, $80
	out PORTA, r20
	call BEEP_DELAY
	ldi r20, $00
	out PORTA, r20
	call BEEP_DELAY
	dec r17
	brne BEEP_LOOP

	pop r17
	pop r18
	pop r20
	sei
	ret

BEEP_DELAY:
	ldi r18, BEEP_PITCH
	lsr r18
BEEP_DELAY_LOOP:
	dec r18
	brne BEEP_DELAY_LOOP
	ret