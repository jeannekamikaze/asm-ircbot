all: ircbot.s
	nasm -f elf ircbot.s
	ld ircbot.o -o ircbot
	
clean:
	@rm -rf ./*.o
	@rm -rf ./ircbot
	
