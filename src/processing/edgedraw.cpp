#include "edgedraw.h"

#include <iostream>

#include "CImg.h"
#include "processing.h"

/**
 * Extract edges from the image using Canny edge detection method.
 *
 * @param image Image to extract edge, with RGB color and single depth.
 * @param method Method to use for edge detection, 0 for grayscale, 1 for RGB.
 * @pre Noise should have been removed on the image in previous steps.
 */
CImg extractEdgeCanny(CImg &image, int method) {
    // Create a new image to store the edge
    CImg edge(image.width(), image.height());
    CImgInt direction(image.width(), image.height());

    // Calculate gradient magnitude for each pixel
    if (method == 0) {
        gradientInGray(image, edge, direction);
    } else {
        gradientInColor(image, edge, direction);
    }

    // print the gradient
    // for (int i = 0; i < gradient.width(); i++) {
    //     for (int j = 0; j < gradient.height(); j++) {
    //         std::cout << "Gradient at (" << i << ", " << j
    //                   << "): " << gradient(i, j).mag << "\t"
    //                   << gradient(i, j).dir << std::endl;
    //     }
    // }

    // Non-maximum Suppression
    nonMaxSuppression(edge, direction);

    return edge;
}

/**
 * Convert colored image to grayscale and calculate gradient
 */
void gradientInGray(CImg &image, CImg &edge, CImgInt &direction) {
    // Convert the image to grayscale
    CImg grayImage(image.width(), image.height(), 1, 3, 0);

    cimg_forXY(image, x, y) {
        // Calculate the grayscale value of the pixel
        unsigned char grayValue = 0.299 * image(x, y, 0) +
                                  0.587 * image(x, y, 1) +
                                  0.114 * image(x, y, 2);

        // Set the grayscale value in the gray image
        grayImage(x, y) = grayValue;
    }

    // Calculate the gradient in the grayscale image
    cimg_forXY(grayImage, x, y) {
        // If the pixel is not at the edge of the image
        if (x > 0 && x < grayImage.width() - 1 && y > 0 &&
            y < grayImage.height() - 1) {
            gradientResp gr = calculateGradient(grayImage, x, y);
            edge(x, y) = gr.mag;
            direction(x, y) = gr.dir;
        }
    }
}

/**
 * Calculate gradient separately in RGB dimension and combine
 */
void gradientInColor(CImg &image, CImg &edge, CImgInt &direction) {
    // TODO: Implement this function
    std::cout << "Error: Function not implemented" << std::endl;
}

/**
 * Calculate gradient for a single pixel
 *
 * @return Gradient magnitude of the pixel
 * @pre The pixel is not at the edge of the image.
 */
gradientResp calculateGradient(CImg &image, int x, int y) {
    static const int SOBEL_X[3][3] = {{-1, 0, 1}, {-2, 0, 2}, {-1, 0, 1}};
    static const int SOBEL_Y[3][3] = {{-1, -2, -1}, {0, 0, 0}, {1, 2, 1}};

    // Calculate the gradient in the x and y directions
    int gradientX = 0;
    int gradientY = 0;
    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            gradientX += SOBEL_X[i + 1][j + 1] * image(x + i, y + j);
            gradientY += SOBEL_Y[i + 1][j + 1] * image(x + i, y + j);
        }
    }

    // Calculate the magnitude of the gradient
    return gradientResp(sqrt(gradientX * gradientX + gradientY * gradientY),
                        atan2(gradientY, gradientX) * 180 / M_PI);
}

/**
 * Apply non-maximum suppression to the gradient image
 */
void nonMaxSuppression(CImg &edge, CImgInt &direction) {
    cimg_forXY(edge, x, y) {
        // If the pixel is not at the edge of the image
        if (x > 0 && x < edge.width() - 1 && y > 0 && y < edge.height() - 1) {
            // Get the direction of the gradient
            int dir = direction(x, y);

            // Check the direction of the gradient
            if (dir < 0) {
                dir += 180;
            }

            // Check the direction of the gradient
            if (dir >= 157.5 || dir < 22.5) {
                if (edge(x, y) < edge(x, y + 1) ||
                    edge(x, y) < edge(x, y - 1)) {
                    edge(x, y) = 0;
                }
            } else if (dir >= 22.5 && dir < 67.5) {
                if (edge(x, y) < edge(x - 1, y + 1) ||
                    edge(x, y) < edge(x + 1, y - 1)) {
                    edge(x, y) = 0;
                }
            } else if (dir >= 67.5 && dir < 112.5) {
                if (edge(x, y) < edge(x - 1, y) ||
                    edge(x, y) < edge(x + 1, y)) {
                    edge(x, y) = 0;
                }
            } else {
                if (edge(x, y) < edge(x - 1, y - 1) ||
                    edge(x, y) < edge(x + 1, y + 1)) {
                    edge(x, y) = 0;
                }
            }
        }
    }
}