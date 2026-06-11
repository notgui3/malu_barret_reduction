cpu:
	gcc malu_cpu.c -o malu_cpu -lm -lcrypto
	./malu_cpu

gpu: malu_gpu.cu
	nvcc -O3 malu_gpu.cu -o malu_gpu -lcrypto
	./malu_gpu