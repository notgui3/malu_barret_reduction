cpu:
	gcc malu_cpu.c -o malu_cpu -lm -lcrypto
	./malu_cpu