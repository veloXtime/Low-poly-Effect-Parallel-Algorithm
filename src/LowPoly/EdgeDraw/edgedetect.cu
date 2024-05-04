#include <cuda_runtime.h>

#include "edgedraw.h"

__constant__ int SOBEL_X[3][3] = {{-1, 0, 1}, {-2, 0, 2}, {-1, 0, 1}};
__constant__ int SOBEL_Y[3][3] = {{-1, -2, -1}, {0, 0, 0}, {1, 2, 1}};
__constant__ unsigned char SUPPRESS_THRESHOLD = GRADIENT_THRESH;
__constant__ int ANCHORS_THRESHOLD = ANCHOR_THRESH;

__global__ void colorToGrayKernel(unsigned char *image,
                                  unsigned char *grayImage, int width,
                                  int height) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    int pixels = width * height;

    if (x < width && y < height) {
        int idx = y * width + x;
        unsigned char r = image[idx];
        unsigned char g = image[idx + pixels];
        unsigned char b = image[idx + 2 * pixels];
        unsigned char grayValue = 0.299f * r + 0.587f * g + 0.114f * b;
        grayImage[idx] = grayValue;
    }
}

__global__ void gradientCalculationKernel(unsigned char *grayImage,
                                          unsigned char *gradient,
                                          float *direction, int width,
                                          int height) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;

    if (x > 0 && x < width - 1 && y > 0 && y < height - 1) {
        int gradientX = 0, gradientY = 0;

        // Apply the Sobel filter
        for (int i = -1; i <= 1; i++) {
            for (int j = -1; j <= 1; j++) {
                int pixel = grayImage[(y + j) * width + (x + i)];
                gradientX += SOBEL_X[i + 1][j + 1] * pixel;
                gradientY += SOBEL_Y[i + 1][j + 1] * pixel;
            }
        }

        int idx = y * width + x;
        gradient[idx] = sqrtf(gradientX * gradientX + gradientY * gradientY);
        direction[idx] = atan2f(gradientY, gradientX) * 180 / M_PI;
    }
}

void gradientInGrayGPU(CImg &image, CImg &gradient, CImgFloat &direction) {
    int width = image.width(), height = image.height();

    // Flatten the image data for CUDA
    unsigned char *d_image, *d_grayImage, *d_gradient;
    float *d_direction;
    size_t imageSize = width * height * 3 * sizeof(unsigned char);
    size_t grayImageSize = width * height * sizeof(unsigned char);
    size_t directionSize = width * height * sizeof(float);

    cudaMalloc(&d_image, imageSize);
    cudaMalloc(&d_grayImage, grayImageSize);
    cudaMalloc(&d_gradient, grayImageSize);
    cudaMalloc(&d_direction, directionSize);

    cudaMemcpy(d_image, image.data(), imageSize, cudaMemcpyHostToDevice);
    cudaMemset(d_gradient, 0, grayImageSize);
    cudaMemset(d_direction, 0, directionSize);

    dim3 blockSize(16, 16);
    dim3 gridSize((width + blockSize.x - 1) / blockSize.x,
                  (height + blockSize.y - 1) / blockSize.y);

    colorToGrayKernel<<<gridSize, blockSize>>>(d_image, d_grayImage, width,
                                               height);
    gradientCalculationKernel<<<gridSize, blockSize>>>(
        d_grayImage, d_gradient, d_direction, width, height);

    // Copy results back to host
    cudaMemcpy(gradient.data(), d_gradient, grayImageSize,
               cudaMemcpyDeviceToHost);
    cudaMemcpy(direction.data(), d_direction, directionSize,
               cudaMemcpyDeviceToHost);

    // Free device memory
    cudaFree(d_image);
    cudaFree(d_grayImage);
    cudaFree(d_gradient);
    cudaFree(d_direction);
}

__global__ void suppressWeakGradientsKernel(unsigned char *gradient, int width,
                                            int height) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;
    if (x < width && y < height) {
        int idx = y * width +
                  x;  // Index into the 1D array representation of the image
        if (gradient[idx] <= SUPPRESS_THRESHOLD) {
            gradient[idx] = 0;
        }
    }
}

void suppressWeakGradientsGPU(CImg &gradient) {
    int width = gradient.width(), height = gradient.height();
    size_t numPixels = width * height;
    unsigned char *d_gradient;

    // Allocate GPU memory
    cudaMalloc(&d_gradient, numPixels * sizeof(unsigned char));

    // Copy data from host to device
    cudaMemcpy(d_gradient, gradient.data(), numPixels * sizeof(unsigned char),
               cudaMemcpyHostToDevice);

    // Define block and grid sizes
    dim3 blockSize(16, 16);
    dim3 gridSize((width + blockSize.x - 1) / blockSize.x,
                  (height + blockSize.y - 1) / blockSize.y);

    // Launch the kernel
    suppressWeakGradientsKernel<<<gridSize, blockSize>>>(d_gradient, width,
                                                         height);

    // Copy the modified data back to the host
    cudaMemcpy(gradient.data(), d_gradient, numPixels * sizeof(unsigned char),
               cudaMemcpyDeviceToHost);

    // Free GPU memory
    cudaFree(d_gradient);
}

__device__ bool isHorizontalCuda(float angle) {
    if ((angle < 45 && angle >= -45) || angle >= 136 || angle < -135) {
        return true;  // horizontal
    } else {
        return false;
    }
}

__global__ void determineAnchorsKernel(unsigned char *gradient,
                                       float *direction, bool *anchor,
                                       int width, int height) {
    int x = blockIdx.x * blockDim.x + threadIdx.x;
    int y = blockIdx.y * blockDim.y + threadIdx.y;

    if (x > 0 && x < width - 1 && y > 0 && y < height - 1 && x % 2 == 0 &&
        y % 2 == 0) {
        float angle = direction[y * width + x];
        int magnitude = gradient[y * width + x];
        int mag1 = 0, mag2 = 0;

        if (isHorizontalCuda(angle)) {
            mag1 = gradient[(y - 1) * width + x];
            mag2 = gradient[(y + 1) * width + x];
        } else {
            mag1 = gradient[y * width + (x - 1)];
            mag2 = gradient[y * width + (x + 1)];
        }

        bool is_anchor = (magnitude - mag1 >= ANCHORS_THRESHOLD) &&
                         (magnitude - mag2 >= ANCHORS_THRESHOLD);
        anchor[y * width + x] = is_anchor;
    }
}

void determineAnchorsGPU(const CImg &gradient, const CImgFloat &direction,
                         CImgBool &anchor) {
    int width = gradient.width();
    int height = gradient.height();
    size_t numPixels = width * height;

    // Device memory pointers
    unsigned char *d_gradient;
    float *d_direction;
    bool *d_anchor;

    // Allocate device memory
    cudaMalloc(&d_gradient, numPixels * sizeof(unsigned char));
    cudaMalloc(&d_direction, numPixels * sizeof(float));
    cudaMalloc(&d_anchor, numPixels * sizeof(bool));

    // Copy data to device
    cudaMemcpy(d_gradient, gradient.data(), numPixels * sizeof(unsigned char),
               cudaMemcpyHostToDevice);
    cudaMemcpy(d_direction, direction.data(), numPixels * sizeof(float),
               cudaMemcpyHostToDevice);
    cudaMemset(d_anchor, 0, numPixels * sizeof(bool));

    // Kernel launch parameters
    dim3 blockSize(16, 16);
    dim3 gridSize((width + blockSize.x - 1) / blockSize.x,
                  (height + blockSize.y - 1) / blockSize.y);

    // Launch kernel
    determineAnchorsKernel<<<gridSize, blockSize>>>(d_gradient, d_direction,
                                                    d_anchor, width, height);

    // Copy results back to host
    cudaMemcpy(anchor.data(), d_anchor, numPixels * sizeof(bool),
               cudaMemcpyDeviceToHost);

    // Free device memory
    cudaFree(d_gradient);
    cudaFree(d_direction);
    cudaFree(d_anchor);
}