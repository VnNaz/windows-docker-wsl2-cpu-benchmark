// Исследование: один арифметический тест на процесс.
// g++ -std=c++17 -O2 benchmark_ops.cpp -o benchmark_ops[.exe]
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <string>
#include <thread>
#include <stdexcept>

#ifdef _WIN32
#include <windows.h>
#else
#include <time.h>
#endif

#if defined(__GNUC__)
#define NOINLINE __attribute__((noinline))
#else
#define NOINLINE
#endif

volatile std::uint64_t sink_int = 0;
volatile double sink_double = 0;

static double process_cpu_seconds() {
#ifdef _WIN32
    FILETIME create_time, exit_time, kernel_time, user_time;
    if (!GetProcessTimes(GetCurrentProcess(), &create_time, &exit_time, &kernel_time, &user_time)) {
        throw std::runtime_error("GetProcessTimes failed");
    }
    ULARGE_INTEGER u, k;
    u.LowPart = user_time.dwLowDateTime;
    u.HighPart = user_time.dwHighDateTime;
    k.LowPart = kernel_time.dwLowDateTime;
    k.HighPart = kernel_time.dwHighDateTime;
    return static_cast<double>(u.QuadPart + k.QuadPart) / 10000000.0;
#else
    struct timespec t;
    if (clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &t) != 0) {
        throw std::runtime_error("clock_gettime failed");
    }
    return static_cast<double>(t.tv_sec) + 1e-9 * static_cast<double>(t.tv_nsec);
#endif
}

static std::int64_t unix_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

NOINLINE static void run_int_add(std::uint64_t n) {
    std::uint64_t value = 1;
    volatile std::uint64_t operand = 123456789;
    for (std::uint64_t i = 0; i < n; ++i) value += operand;
    sink_int = value;
}
NOINLINE static void run_int_sub(std::uint64_t n) {
    std::uint64_t value = 1000000000;
    volatile std::uint64_t operand = 98765431;
    for (std::uint64_t i = 0; i < n; ++i) value -= operand;
    sink_int = value;
}
NOINLINE static void run_int_mul(std::uint64_t n) {
    std::uint64_t value = 3;
    volatile std::uint64_t operand = 3;
    for (std::uint64_t i = 0; i < n; ++i) value *= operand;
    sink_int = value;
}
NOINLINE static void run_int_div(std::uint64_t n) {
    // Nontrivial division by a volatile value. Keep the dividend nonzero
    // on every iteration, so division does not degenerate into 0 / divisor.
    // The OR has small fixed cost, equal in the two environments.
    std::uint64_t value = 1234567890123456789ULL;
    volatile std::uint64_t operand = 7;
    for (std::uint64_t i = 0; i < n; ++i) {
        value = (value | (1ULL << 60)) / operand;
    }
    sink_int = value;
}
NOINLINE static void run_double_add(std::uint64_t n) {
    double value = 1.0;
    volatile double operand = 0.000001;
    for (std::uint64_t i = 0; i < n; ++i) value += operand;
    sink_double = value;
}
NOINLINE static void run_double_sub(std::uint64_t n) {
    double value = 2000.0;
    volatile double operand = 0.000001;
    for (std::uint64_t i = 0; i < n; ++i) value -= operand;
    sink_double = value;
}
NOINLINE static void run_double_mul(std::uint64_t n) {
    double value = 1.0;
    volatile double operand = 1.000000001;
    for (std::uint64_t i = 0; i < n; ++i) value *= operand;
    sink_double = value;
}
NOINLINE static void run_double_div(std::uint64_t n) {
    double value = 1.0;
    volatile double operand = 1.000000001;
    for (std::uint64_t i = 0; i < n; ++i) value /= operand;
    sink_double = value;
}

int main(int argc, char** argv) {
    if (argc < 3 || argc > 4) {
        std::cerr << "usage: benchmark_ops TEST ITERATIONS [TARGET_UNIX_MS]\n";
        return 2;
    }
    try {
        std::string test = argv[1];
        std::uint64_t n = std::stoull(argv[2]);
        std::int64_t target = argc == 4 ? std::stoll(argv[3]) : 0;
        if (n == 0) throw std::invalid_argument("iterations must be positive");
        // Wait outside the measured interval. A common target synchronizes the group.
        while (target > 0 && unix_ms() < target) {
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
        }
        auto cpu_before = process_cpu_seconds();
        auto stamp_before = unix_ms();
        auto wall_before = std::chrono::steady_clock::now();
        if      (test == "int_add") run_int_add(n);
        else if (test == "int_sub") run_int_sub(n);
        else if (test == "int_mul") run_int_mul(n);
        else if (test == "int_div") run_int_div(n);
        else if (test == "double_add") run_double_add(n);
        else if (test == "double_sub") run_double_sub(n);
        else if (test == "double_mul") run_double_mul(n);
        else if (test == "double_div") run_double_div(n);
        else throw std::invalid_argument("unknown test: " + test);
        auto wall_after = std::chrono::steady_clock::now();
        auto stamp_after = unix_ms();
        auto cpu_after = process_cpu_seconds();
        double wall = std::chrono::duration<double>(wall_after-wall_before).count();
        double cpu = cpu_after-cpu_before;
        std::cout << "test,iterations,start_unix_ms,end_unix_ms,target_unix_ms,wall_sec,cpu_sec,mops,checksum\n";
        std::cout << test << "," << n << "," << stamp_before << "," << stamp_after << "," << target << ","
                  << std::fixed << std::setprecision(9) << wall << "," << cpu << ","
                  << std::setprecision(6) << static_cast<double>(n)/wall/1000000.0 << ",";
        if (test.rfind("int_", 0) == 0) std::cout << sink_int;
        else std::cout << std::setprecision(17) << sink_double;
        std::cout << "\n";
        return 0;
    } catch (const std::exception& e) {
        std::cerr << "error: " << e.what() << "\n";
        return 1;
    }
}
