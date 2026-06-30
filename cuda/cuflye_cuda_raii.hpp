// SPDX-License-Identifier: BSD-3-Clause

#pragma once

#include <cuda_runtime_api.h>

#include <cstddef>
#include <stdexcept>
#include <string>

namespace cuflye
{
namespace cuda_raii
{
inline void checkCuda(cudaError_t status, const std::string& action)
{
	if (status != cudaSuccess)
	{
		throw std::runtime_error(action + ": code=" +
								 std::to_string(static_cast<int>(status)) +
								 " name=" + cudaGetErrorName(status) +
								 " text=" + cudaGetErrorString(status));
	}
}

template <class T>
class DeviceBuffer
{
public:
	DeviceBuffer() = default;

	DeviceBuffer(size_t bytes, const std::string& label)
	{
		allocate(bytes, label);
	}

	~DeviceBuffer()
	{
		resetNoThrow();
	}

	DeviceBuffer(const DeviceBuffer&) = delete;
	DeviceBuffer& operator=(const DeviceBuffer&) = delete;

	DeviceBuffer(DeviceBuffer&& other) noexcept
	{
		moveFrom(other);
	}

	DeviceBuffer& operator=(DeviceBuffer&& other) noexcept
	{
		if (this != &other)
		{
			resetNoThrow();
			moveFrom(other);
		}
		return *this;
	}

	void allocate(size_t bytes, const std::string& label)
	{
		resetNoThrow();
		if (bytes == 0) return;

		void* raw = nullptr;
		checkCuda(cudaMalloc(&raw, bytes), "allocate CUDA device buffer " + label);
		ptr_ = static_cast<T*>(raw);
		bytes_ = bytes;
	}

	bool ensureCapacity(size_t bytes, const std::string& label)
	{
		if (bytes <= bytes_) return false;
		allocate(bytes, label);
		return bytes > 0;
	}

	void resetNoThrow() noexcept
	{
		if (ptr_)
		{
			(void)cudaFree(ptr_);
			ptr_ = nullptr;
			bytes_ = 0;
		}
	}

	T* get() const noexcept
	{
		return ptr_;
	}

	size_t bytes() const noexcept
	{
		return bytes_;
	}

	explicit operator bool() const noexcept
	{
		return ptr_ != nullptr;
	}

private:
	void moveFrom(DeviceBuffer& other) noexcept
	{
		ptr_ = other.ptr_;
		bytes_ = other.bytes_;
		other.ptr_ = nullptr;
		other.bytes_ = 0;
	}

	T* ptr_ = nullptr;
	size_t bytes_ = 0;
};

class CudaEvent
{
public:
	CudaEvent() = default;

	explicit CudaEvent(const std::string& label)
	{
		create(label);
	}

	~CudaEvent()
	{
		resetNoThrow();
	}

	CudaEvent(const CudaEvent&) = delete;
	CudaEvent& operator=(const CudaEvent&) = delete;

	CudaEvent(CudaEvent&& other) noexcept
	{
		moveFrom(other);
	}

	CudaEvent& operator=(CudaEvent&& other) noexcept
	{
		if (this != &other)
		{
			resetNoThrow();
			moveFrom(other);
		}
		return *this;
	}

	void create(const std::string& label)
	{
		resetNoThrow();
		checkCuda(cudaEventCreate(&event_), "create CUDA event " + label);
	}

	void resetNoThrow() noexcept
	{
		if (event_)
		{
			(void)cudaEventDestroy(event_);
			event_ = nullptr;
		}
	}

	cudaEvent_t get() const noexcept
	{
		return event_;
	}

private:
	void moveFrom(CudaEvent& other) noexcept
	{
		event_ = other.event_;
		other.event_ = nullptr;
	}

	cudaEvent_t event_ = nullptr;
};
}
}
