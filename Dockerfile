FROM gcc:15.2.0
WORKDIR /app
COPY benchmark_ops.cpp ./
RUN g++ -std=c++17 -O2 benchmark_ops.cpp -o benchmark_ops
ENTRYPOINT ["/app/benchmark_ops"]
