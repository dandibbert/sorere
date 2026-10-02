// SorereHost.mm
// Minimal iPhone -> BlackHole host. No solunad playback pipeline.

#import <CoreAudio/CoreAudio.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dns_sd.h>

#include <arpa/inet.h>
#include <algorithm>
#include <climits>
#include <atomic>
#include <cmath>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <vector>
#include <unistd.h>
#include <sys/socket.h>
#include <netinet/in.h>

namespace {

constexpr uint16_t kPort = 5004;
constexpr uint32_t kChannels = 2;
constexpr uint32_t kRate = 48000;
constexpr size_t kRtpHeader = 12;
constexpr size_t kRtpExtHeader = 4;
constexpr size_t kOstpHeader = 8;
constexpr size_t kHeaderBytes = kRtpHeader + kRtpExtHeader + kOstpHeader;
constexpr size_t kRingFrames = kRate * 2;

std::atomic<bool> gRunning{true};

void signal_handler(int) {
    gRunning.store(false);
}

struct StereoRing {
    std::vector<float> data = std::vector<float>(kRingFrames * 2, 0.0f);
    std::atomic<uint64_t> write_pos{0};
    std::atomic<uint64_t> read_pos{0};
    std::atomic<uint64_t> dropped_frames{0};

    void reset() {
        write_pos.store(0, std::memory_order_release);
        read_pos.store(0, std::memory_order_release);
        dropped_frames.store(0, std::memory_order_release);
    }

    void write(const float* src, size_t frames) {
        if (!src || frames == 0) return;
        uint64_t w = write_pos.load(std::memory_order_relaxed);
        uint64_t r = read_pos.load(std::memory_order_acquire);
        uint64_t used = w - r;
        size_t free_frames = used < kRingFrames ? static_cast<size_t>(kRingFrames - used) : 0;
        if (frames > free_frames) {
            dropped_frames.fetch_add(frames, std::memory_order_relaxed);
            return;
        }

        for (size_t i = 0; i < frames; ++i) {
            size_t idx = static_cast<size_t>((w + i) % kRingFrames) * 2;
            data[idx] = src[i * 2];
            data[idx + 1] = src[i * 2 + 1];
        }
        write_pos.store(w + frames, std::memory_order_release);
    }

    size_t read(float* dst, size_t frames) {
        if (!dst || frames == 0) return 0;
        uint64_t r = read_pos.load(std::memory_order_relaxed);
        uint64_t w = write_pos.load(std::memory_order_acquire);
        size_t avail = static_cast<size_t>(w - r);
        size_t count = std::min(frames, avail);

        for (size_t i = 0; i < count; ++i) {
            size_t idx = static_cast<size_t>((r + i) % kRingFrames) * 2;
            dst[i * 2] = data[idx];
            dst[i * 2 + 1] = data[idx + 1];
        }
        read_pos.store(r + count, std::memory_order_release);
        return count;
    }

    size_t available() const {
        uint64_t r = read_pos.load(std::memory_order_acquire);
        uint64_t w = write_pos.load(std::memory_order_acquire);
        return static_cast<size_t>(w - r);
    }
};

class BlackHoleWriter {
public:
    ~BlackHoleWriter() { stop(); }

    bool start(bool test_tone) {
        test_tone_ = test_tone;
        device_ = find_device("BlackHole 2ch");
        if (device_ == kAudioObjectUnknown) {
            fprintf(stderr, "ERROR: BlackHole 2ch was not found.\n");
            return false;
        }

        if (!prepare_rate()) return false;

        OSStatus st = AudioDeviceCreateIOProcID(device_, io_proc, this, &io_proc_id_);
        if (st != noErr || !io_proc_id_) {
            fprintf(stderr, "ERROR: Could not attach to BlackHole (%d).\n", (int)st);
            return false;
        }

        st = AudioDeviceStart(device_, io_proc_id_);
        if (st != noErr) {
            fprintf(stderr, "ERROR: Could not start BlackHole (%d).\n", (int)st);
            AudioDeviceDestroyIOProcID(device_, io_proc_id_);
            io_proc_id_ = nullptr;
            return false;
        }

        started_ = true;
        return true;
    }

    void stop() {
        if (started_ && device_ != kAudioObjectUnknown && io_proc_id_) {
            AudioDeviceStop(device_, io_proc_id_);
            AudioDeviceDestroyIOProcID(device_, io_proc_id_);
        }
        started_ = false;
        io_proc_id_ = nullptr;
        device_ = kAudioObjectUnknown;
    }

    StereoRing& ring() { return ring_; }
    float input_peak() const { return input_peak_.load(std::memory_order_relaxed); }
    uint64_t rendered_frames() const { return rendered_frames_.load(std::memory_order_relaxed); }
    uint64_t nonzero_output_samples() const { return nonzero_output_samples_.load(std::memory_order_relaxed); }

private:
    static AudioDeviceID find_device(const char* wanted) {
        AudioObjectPropertyAddress addr = {
            kAudioHardwarePropertyDevices,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };
        UInt32 size = 0;
        if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &addr, 0, nullptr, &size) != noErr)
            return kAudioObjectUnknown;

        std::vector<AudioDeviceID> ids(size / sizeof(AudioDeviceID));
        if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, nullptr, &size, ids.data()) != noErr)
            return kAudioObjectUnknown;

        for (AudioDeviceID id : ids) {
            CFStringRef name = nullptr;
            UInt32 nsize = sizeof(name);
            AudioObjectPropertyAddress naddr = {
                kAudioDevicePropertyDeviceNameCFString,
                kAudioObjectPropertyScopeGlobal,
                kAudioObjectPropertyElementMain
            };
            if (AudioObjectGetPropertyData(id, &naddr, 0, nullptr, &nsize, &name) != noErr || !name)
                continue;
            char buf[256] = {};
            bool ok = CFStringGetCString(name, buf, sizeof(buf), kCFStringEncodingUTF8);
            CFRelease(name);
            if (ok && std::strcmp(buf, wanted) == 0) return id;
        }
        return kAudioObjectUnknown;
    }

    bool prepare_rate() {
        AudioObjectPropertyAddress addr = {
            kAudioDevicePropertyNominalSampleRate,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMain
        };

        Float64 rate = 0;
        UInt32 size = sizeof(rate);
        if (AudioObjectGetPropertyData(device_, &addr, 0, nullptr, &size, &rate) != noErr) {
            fprintf(stderr, "ERROR: Could not read BlackHole sample rate.\n");
            return false;
        }

        if (std::fabs(rate - static_cast<double>(kRate)) > 1.0) {
            Boolean settable = false;
            if (AudioObjectIsPropertySettable(device_, &addr, &settable) == noErr && settable) {
                Float64 desired = kRate;
                AudioObjectSetPropertyData(device_, &addr, 0, nullptr, sizeof(desired), &desired);
                usleep(100000);
                size = sizeof(rate);
                AudioObjectGetPropertyData(device_, &addr, 0, nullptr, &size, &rate);
            }
        }

        if (std::fabs(rate - static_cast<double>(kRate)) > 1.0) {
            fprintf(stderr, "ERROR: BlackHole is %.0f Hz; Sorere needs 48000 Hz.\n", rate);
            return false;
        }
        return true;
    }

    static OSStatus io_proc(AudioObjectID,
                            const AudioTimeStamp*,
                            const AudioBufferList* input,
                            const AudioTimeStamp*,
                            AudioBufferList* output,
                            const AudioTimeStamp*,
                            void* context) {
        auto* self = static_cast<BlackHoleWriter*>(context);
        if (!self) return noErr;
        self->handle_input(input);
        self->render(output);
        return noErr;
    }

    void handle_input(const AudioBufferList* input) {
        if (!input) return;
        float peak = 0.0f;
        for (UInt32 b = 0; b < input->mNumberBuffers; ++b) {
            const AudioBuffer& ab = input->mBuffers[b];
            if (!ab.mData || ab.mDataByteSize == 0) continue;
            const float* p = static_cast<const float*>(ab.mData);
            size_t count = ab.mDataByteSize / sizeof(float);
            for (size_t i = 0; i < count; ++i) {
                float v = std::fabs(p[i]);
                if (v > peak) peak = v;
            }
        }
        float prev = input_peak_.load(std::memory_order_relaxed);
        if (peak > prev) input_peak_.store(peak, std::memory_order_relaxed);
        else input_peak_.store(prev * 0.92f, std::memory_order_relaxed);
    }

    void render(AudioBufferList* output) {
        if (!output || output->mNumberBuffers == 0) return;

        UInt32 frames = UINT32_MAX;
        for (UInt32 b = 0; b < output->mNumberBuffers; ++b) {
            const AudioBuffer& ab = output->mBuffers[b];
            if (!ab.mData || ab.mNumberChannels == 0) continue;
            UInt32 f = ab.mDataByteSize / (ab.mNumberChannels * sizeof(float));
            frames = std::min(frames, f);
        }
        if (frames == UINT32_MAX || frames == 0) return;

        if (scratch_.size() < static_cast<size_t>(frames) * 2)
            scratch_.resize(static_cast<size_t>(frames) * 2);

        if (test_tone_) {
            for (UInt32 f = 0; f < frames; ++f) {
                float s = 0.25f * std::sin(2.0 * M_PI * 440.0 * tone_phase_ / kRate);
                tone_phase_ += 1.0;
                if (tone_phase_ >= kRate) tone_phase_ -= kRate;
                scratch_[f * 2] = s;
                scratch_[f * 2 + 1] = s;
            }
        } else {
            size_t got = ring_.read(scratch_.data(), frames);
            if (got < frames) {
                std::memset(scratch_.data() + got * 2, 0,
                            (static_cast<size_t>(frames) - got) * 2 * sizeof(float));
            }
        }

        uint64_t nz = 0;
        UInt32 first_channel = 0;
        for (UInt32 b = 0; b < output->mNumberBuffers; ++b) {
            AudioBuffer& ab = output->mBuffers[b];
            if (!ab.mData || ab.mNumberChannels == 0) {
                first_channel += ab.mNumberChannels;
                continue;
            }
            std::memset(ab.mData, 0, ab.mDataByteSize);
            float* dst = static_cast<float*>(ab.mData);
            UInt32 local_frames = ab.mDataByteSize / (ab.mNumberChannels * sizeof(float));
            UInt32 use_frames = std::min(frames, local_frames);

            for (UInt32 f = 0; f < use_frames; ++f) {
                for (UInt32 c = 0; c < ab.mNumberChannels; ++c) {
                    UInt32 device_channel = first_channel + c;
                    if (device_channel < 2) {
                        float s = scratch_[f * 2 + device_channel];
                        dst[f * ab.mNumberChannels + c] = s;
                        if (std::fabs(s) > 0.00001f) ++nz;
                    }
                }
            }
            first_channel += ab.mNumberChannels;
        }
        rendered_frames_.fetch_add(frames, std::memory_order_relaxed);
        nonzero_output_samples_.fetch_add(nz, std::memory_order_relaxed);
    }

    AudioDeviceID device_ = kAudioObjectUnknown;
    AudioDeviceIOProcID io_proc_id_ = nullptr;
    bool started_ = false;
    bool test_tone_ = false;
    StereoRing ring_;
    std::vector<float> scratch_ = std::vector<float>(8192 * 2, 0.0f);
    double tone_phase_ = 0.0;
    std::atomic<float> input_peak_{0.0f};
    std::atomic<uint64_t> rendered_frames_{0};
    std::atomic<uint64_t> nonzero_output_samples_{0};
};

class BonjourAdvertiser {
public:
    bool start() {
        uint16_t port = htons(kPort);
        DNSServiceErrorType err = DNSServiceRegister(
            &ref_, 0, 0, "Sorere Host", "_soluna._tcp",
            nullptr, nullptr, port, 0, nullptr, nullptr, nullptr);
        if (err != kDNSServiceErr_NoError) return false;

        thread_ = std::thread([this]() {
            int fd = DNSServiceRefSockFD(ref_);
            while (gRunning.load() && ref_ && fd >= 0) {
                fd_set set;
                FD_ZERO(&set);
                FD_SET(fd, &set);
                timeval tv{1, 0};
                int rc = select(fd + 1, &set, nullptr, nullptr, &tv);
                if (rc > 0) DNSServiceProcessResult(ref_);
            }
        });
        return true;
    }

    ~BonjourAdvertiser() {
        if (ref_) {
            DNSServiceRefDeallocate(ref_);
            ref_ = nullptr;
        }
        if (thread_.joinable()) thread_.join();
    }

private:
    DNSServiceRef ref_ = nullptr;
    std::thread thread_;
};

bool parse_audio_packet(const uint8_t* packet, size_t length,
                        std::vector<float>& out, size_t& frames, float& peak) {
    frames = 0;
    peak = 0.0f;
    if (!packet || length < kHeaderBytes + 4) return false;

    uint8_t version = packet[0] >> 6;
    bool extension = (packet[0] & 0x10) != 0;
    uint8_t payload_type = packet[1] & 0x7F;
    if (version != 2 || !extension || payload_type != 96) return false;

    uint16_t profile = static_cast<uint16_t>(packet[12] << 8 | packet[13]);
    uint16_t ext_words = static_cast<uint16_t>(packet[14] << 8 | packet[15]);
    if (profile != 0x4F53 || ext_words != 2) return false;

    size_t data_len = length - kHeaderBytes;
    size_t payload_bytes = data_len;
    if (data_len >= 4 && ((data_len - 4) % sizeof(int32_t) == 0))
        payload_bytes = data_len - 4;

    if (payload_bytes == 0 || payload_bytes % (sizeof(int32_t) * kChannels) != 0)
        return false;

    frames = payload_bytes / (sizeof(int32_t) * kChannels);
    out.resize(frames * 2);
    const uint8_t* payload = packet + kHeaderBytes;

    for (size_t i = 0; i < frames * 2; ++i) {
        int32_t v = 0;
        std::memcpy(&v, payload + i * sizeof(int32_t), sizeof(v));
        float s = static_cast<float>(v) / 8388608.0f;
        if (s > 1.0f) s = 1.0f;
        if (s < -1.0f) s = -1.0f;
        out[i] = s;
        peak = std::max(peak, std::fabs(s));
    }
    return true;
}

int run_network(BlackHoleWriter& writer) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) {
        fprintf(stderr, "ERROR: Could not create UDP socket.\n");
        return 1;
    }

    int reuse = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(kPort);
    if (bind(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0) {
        fprintf(stderr, "ERROR: UDP port 5004 is already in use.\n");
        close(fd);
        return 1;
    }

    timeval timeout{0, 250000};
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));

    std::vector<uint8_t> packet(65536);
    std::vector<float> samples;
    bool announced_packet = false;
    bool announced_signal = false;

    while (gRunning.load()) {
        ssize_t n = recv(fd, packet.data(), packet.size(), 0);
        if (n <= 0) continue;

        size_t frames = 0;
        float peak = 0.0f;
        if (!parse_audio_packet(packet.data(), static_cast<size_t>(n), samples, frames, peak))
            continue;

        if (!announced_packet) {
            printf("iPhone connected\n");
            fflush(stdout);
            announced_packet = true;
        }
        if (!announced_signal && peak > 0.001f) {
            printf("Audio flowing to BlackHole\n");
            fflush(stdout);
            announced_signal = true;
        }

        writer.ring().write(samples.data(), frames);
    }

    close(fd);
    return 0;
}

} // namespace

int main(int argc, char** argv) {
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    bool test_tone = (argc > 1 && std::strcmp(argv[1], "--test-tone") == 0);

    BlackHoleWriter writer;
    if (!writer.start(test_tone)) return 1;

    printf("BlackHole ready\n");
    fflush(stdout);

    if (test_tone) {
        printf("Sending test tone…\n");
        fflush(stdout);

        // Give BlackHole time to feed the output stream back to its input side.
        for (int i = 0; i < 30 && gRunning.load(); ++i) {
            usleep(100000);
            if (writer.input_peak() > 0.01f) {
                printf("BlackHole loopback confirmed\n");
                fflush(stdout);
                while (gRunning.load()) usleep(200000);
                return 0;
            }
        }

        fprintf(stderr,
                "ERROR: Test tone was rendered, but BlackHole input stayed silent. "
                "Reinstall/restart BlackHole or coreaudiod.\n");
        return 2;
    }

    BonjourAdvertiser bonjour;
    if (!bonjour.start()) {
        fprintf(stderr, "ERROR: Bonjour advertising failed.\n");
        return 1;
    }

    printf("Waiting for iPhone…\n");
    fflush(stdout);
    return run_network(writer);
}
