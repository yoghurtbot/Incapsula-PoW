# Incapsula PoW SHA-1 CUDA Solver

A high-performance GPU-accelerated solver for the Incapsula proof-of-work SHA-1 algorithm. This tool leverages NVIDIA CUDA to brute-force nonces in parallel, dramatically reducing solve times compared to a CPU implementation.

---

## Overview

When accessing certain protected resources, Incapsula issues a proof-of-work challenge: a client must find a nonce that, when combined with a salt and fed into the SHA-1 algorithm, matches a server-provided target hash within a time limit. This solver:

* Reads the time limit (`T`), target hash (`D`), and salt (`S`) from script challenge data.
* Launches thousands of CUDA threads to test nonces in parallel.
* Uses constant memory and unrolled loops for maximum throughput.
* Reports the first valid nonce (if found) and timing statistics.

## Example Input Data

The reese84 script contains PoW information which is encoded as base64. Example:
```
eyJjIjoie1widFwiOjE2Nzc3MjE1LFwiZFwiOlwiNDk3Zjg4MTM3NTE5MDc4ZTZhY2U3MTk3NzA5N2M3ZDg5ZWY1NGYyZVwiLFwic1wiOlwiNDllYWZhZTE1ODQ0NGFmNjkxMzUyN2Y5Yzk5N2U3NjhcIn0iLCJzIjoiY1BPL2tONmtYeGFVQWlUSkpRbmJCMTdSR1Jsc2JSemI3WTJmUkkxWTdNR3M4NXJZOTgrNHZVeGdZc01OZ1YrVVRDUmhGMHFPNlRWRjg5OTU1aExqckE2Wk96TFNaVUNGZDJNNUlHSHBBMWdNYmJiYzduNVN2bkFzSWNuRnlVcXRpa3J5Z3ZVRnppZ1pRR1l6In0=
```

Decoding it we get:
```json
{
  "c": "{\"t\":16777215,\"d\":\"497f88137519078e6ace71977097c7d89ef54f2e\",\"s\":\"49eafae158444af6913527f9c997e768\"}",
  "s": "cPO/kN6kXxaUAiTJJQnbB17RGRlsbRzb7Y2fRI1Y7MGs85rY98+4vUxgYsMNgV+UTCRhF0qO6TVF89955hLjrA6ZOzLSZUCFd2M5IGHpA1gMbbbc7n5SvnAsIcnFyUqtikrygvUFzigZQGYz"
}
```

### Extracting Parameters

1. Parse the inner `c` string as JSON.
2. Read the properties:

   * `t`: time limit in milliseconds
   * `d`: target hash (20-byte SHA-1) in hex
   * `s`: salt (16 bytes) in hex

For the example above, you would use:

```text
T = 16777215              # max execution time in milliseconds
D = 497f88137519078e6ace71977097c7d89ef54f2e  # 20-byte SHA-1 target
S = 49eafae158444af6913527f9c997e768          # 16-byte salt
```

## Requirements

* Windows 10 or later
* NVIDIA GPU with compute capability 5.0 or higher
* [CUDA Toolkit](https://developer.nvidia.com/cuda-toolkit) 10.0+
* A C++11-compatible compiler (Visual Studio 2017+ recommended)

## Build Instructions (Windows)

### Using NVCC Directly

1. Open a "x64 Native Tools Command Prompt for VS".

2. Navigate to the project root (where `pow_solver.cu` resides).

3. Compile with:

   ```bat
   nvcc -O3 -std=c++11 -o pow_solver.exe pow_solver.cu
   ```

4. Ensure `pow_solver.exe` was created successfully.

## Usage

```bat
pow_solver.exe <T_ms> <D_hex20> <S_hex16>
```

* `<T_ms>`: time limit (ms)
* `<D_hex20>`: 20-byte target hash in hex
* `<S_hex16>`: 16-byte salt in hex

### Example

```bat
pow_solver.exe 16777215 497f88137519078e6ace71977097c7d89ef54f2e 49eafae158444af6913527f9c997e768
```

Output will look like:

```
foundNonce: 12345678
iterations: 1048576
timeTaken: 36 ms
```

If no nonce is found within the time limit, you’ll see:

```
No valid nonce found in 1048576 iterations within 16777215 ms
```

## Performance Comparison

| Platform | Hardware                    | Time to Solve      |
| -------- | --------------------------- | ------------------ |
| GPU      | NVIDIA GeForce RTX 3070          | \~36 ms            |
| CPU      | Intel Core i9-14900K @3.2GHz | \~21,000 ms (21 s) |

**Speedup:** **≈583× faster** on the GPU than on the CPU.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
