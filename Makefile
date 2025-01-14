#******************************************************************************
#MIT License
#
#Copyright (c) 2016 Antti-Pekka Hynninen
#Copyright (c) 2016 Oak Ridge National Laboratory (UT-Batelle)
#
#Permission is hereby granted, free of charge, to any person obtaining a copy
#of this software and associated documentation files (the "Software"), to deal
#in the Software without restriction, including without limitation the rights
#to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the Software is
#furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all
#copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
#SOFTWARE.
#*******************************************************************************

#################### User Settings ####################

# C++ compiler
HOST_CC = hipcc
GPU_CC = hipcc

# CUDA compiler
CUDAC = hipcc

# Enable nvvp profiling of CPU code by using "make ENABLE_NVTOOLS=1"
# If aligned_alloc() is not available, use "make NO_ALIGNED_ALLOC=1"

# SM versions for which code is generated must be sm_30 and above
GENCODE_SM35  := -gencode arch=compute_35,code=sm_35
GENCODE_SM50  := -gencode arch=compute_50,code=sm_50
GENCODE_SM52  := -gencode arch=compute_52,code=sm_52
GENCODE_SM61  := -gencode arch=compute_61,code=sm_61
GENCODE_SM70  := -gencode arch=compute_70,code=sm_70
GENCODE_FLAGS := $(GENCODE_SM50) $(GENCODE_SM52) $(GENCODE_SM61) $(GENCODE_SM70)

#######################################################

# Detect OS
ifeq ($(shell uname -a|grep Linux|wc -l|tr -d ' '), 1)
OS = linux
endif

ifeq ($(shell uname -a|grep titan|wc -l|tr -d ' '), 1)
OS = linux
endif

ifeq ($(shell uname -a|grep Darwin|wc -l|tr -d ' '), 1)
OS = osx
endif

# Detect x86_64 vs. Power
CPU = unknown

ifeq ($(shell uname -a|grep x86_64|wc -l|tr -d ' '), 1)
CPU = x86_64
endif

ifeq ($(shell uname -a|grep ppc64|wc -l|tr -d ' '), 1)
CPU = ppc64
endif

# Set optimization level
OPTLEV = -O3

# Defines
DEFS =

ifdef ENABLE_NVTOOLS
DEFS += -DENABLE_NVTOOLS
endif

ifdef NO_ALIGNED_ALLOC
DEFS += -DNO_ALIGNED_ALLOC
endif

OBJSLIB = build/cutt.o build/cuttplan.o build/cuttkernel.o build/cuttGpuModel.o build/CudaMem.o build/CudaUtils.o build/cuttTimer.o build/cuttGpuModelKernel.o
OBJSTEST = build/cutt_test.o build/TensorTester.o build/CudaMem.o build/CudaUtils.o build/cuttTimer.o
OBJSBENCH = build/cutt_bench.o build/TensorTester.o build/CudaMem.o build/CudaUtils.o build/cuttTimer.o build/CudaMemcpy.o
OBJS = $(OBJSLIB) $(OBJSTEST) $(OBJSBENCH)

CUDAROOT = $(subst /bin/,,$(dir $(shell which $(CUDAC))))

#CFLAGS = -I${CUDAROOT}/include -std=c++11 $(DEFS) $(OPTLEV) -fPIC -D__HIP_PLATFORM_NVCC__
CFLAGS = -I${CUDAROOT}/include -std=c++11 $(DEFS) $(OPTLEV) -fPIC -D__HIP_PLATFORM_HCC__ -D__HIP_ROCclr__
ifeq ($(CPU),x86_64)
CFLAGS += -march=native -fPIC
endif

#CUDA_CFLAGS = -ccbin $(GPU_CC) -I${CUDAROOT}/include -std=c++11 $(OPTLEV) -Xptxas -dlcm=ca -lineinfo $(GENCODE_FLAGS) --resource-usage -Xcompiler -fPIC -D_FORCE_INLINES -x cu -Wno-deprecated-declarations
CUDA_CFLAGS = --amdgpu-target=gfx906,gfx90a -std=c++11 $(OPTLEV) -D_FORCE_INLINES -fPIC

ifeq ($(OS),osx)
CUDA_LFLAGS = -L$(CUDAROOT)/lib
else
#CUDA_LFLAGS = -L$(CUDAROOT)/lib64
endif

CUDA_LFLAGS += -fPIC

#CUDA_LFLAGS += -Llib -lcudart -lcutt
ifdef ENABLE_NVTOOLS
CUDA_LFLAGS += -lnvToolsExt
endif

all: create_build lib/libcutt.a bin/cutt_test bin/cutt_bench

create_build:
	mkdir -p build

lib/libcutt.a: $(OBJSLIB)
	mkdir -p lib
	rm -f lib/libcutt.a
	ar -cvq lib/libcutt.a $(OBJSLIB)
	mkdir -p include
	cp -f src/cutt.h include/cutt.h

bin/cutt_test : lib/libcutt.a $(OBJSTEST)
	mkdir -p bin
	$(HOST_CC) -o bin/cutt_test -lamdhip64 $(OBJSTEST) -Llib -lcutt $(CUDA_LFLAGS)

bin/cutt_bench : lib/libcutt.a $(OBJSBENCH)
	mkdir -p bin
	$(HOST_CC) -o bin/cutt_bench -lamdhip64 $(OBJSBENCH) -Llib -lcutt $(CUDA_LFLAGS)

clean:
	rm -f $(OBJS)
	rm -f build/*.d
	rm -f *~
	rm -f lib/libcutt.a
	rm -f bin/cutt_test
	rm -f bin/cutt_bench

# Pull in dependencies that already exist
-include $(OBJS:.o=.d)

# build/%.o : src/%.cu
# 	$(CUDAC) -c $(CUDA_CFLAGS) -o build/$*.o $<
# 	echo -e 'build/\c' > build/$*.d
# 	$(CUDAC) -M $(CUDA_CFLAGS) $< >> build/$*.d


build/CudaMemcpy.o : src/CudaMemcpy.cpp
	$(CUDAC) -c $(CUDA_CFLAGS) -o $*.o $<
	echo -e 'build/\c' > $*.d
	$(CUDAC) -M $(CUDA_CFLAGS) $< >> $*.d

build/CudaUtils.o : src/CudaUtils.cpp
	$(CUDAC) -c $(CUDA_CFLAGS) -o $*.o $<
	echo -e 'build/\c' > $*.d
	$(CUDAC) -M $(CUDA_CFLAGS) $< >> $*.d

build/TensorTester.o : src/TensorTester.cpp
	$(CUDAC) -c $(CUDA_CFLAGS) -o $*.o $<
	echo -e 'build/\c' > $*.d
	$(CUDAC) -M $(CUDA_CFLAGS) $< >> $*.d

build/cuttGpuModelKernel.o : src/cuttGpuModelKernel.cpp
	$(CUDAC) -c $(CUDA_CFLAGS) -o $*.o $<
	echo -e 'build/\c' > $*.d
	$(CUDAC) -M $(CUDA_CFLAGS) $< >> $*.d

build/cuttkernel.o : src/cuttkernel.cpp
	$(CUDAC) -c $(CUDA_CFLAGS) -o $*.o $<
	echo -e 'build/\c' > $*.d
	$(CUDAC) -M $(CUDA_CFLAGS) $< >> $*.d


build/%.o : src/%.cpp
	$(HOST_CC) -c $(CFLAGS) -o build/$*.o $<
	echo -e 'build/\c' > build/$*.d
	$(HOST_CC) -M $(CFLAGS) $< >> build/$*.d
