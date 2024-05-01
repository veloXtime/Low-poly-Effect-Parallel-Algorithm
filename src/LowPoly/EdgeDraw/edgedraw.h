#ifndef EDGE_DRAW_H
#define EDGE_DRAW_H

#include "CImg.h"

using CImg = cimg_library::CImg<unsigned char>;
using CImgBool = cimg_library::CImg<bool>;
using CImgFloat = cimg_library::CImg<float>;

struct gradientResp {
    float mag;  // magnitude of gradient
    float dir;  // direction of the gradient

    gradientResp(float _mag, float _dir) : mag(_mag), dir(_dir) {}
};
void gradientInGray(CImg &image, CImg &gradient, CImgFloat &direction);
void gradientInColor(CImg &image, CImg &gradient, CImgFloat &direction);
gradientResp calculateGradient(CImg &image, int x, int y);
void nonMaxSuppression(CImg &edge, CImg &gradient, CImgFloat &direction);
int discretizeDirection(float angle);
void trackEdge(CImg &edge);
void mark(CImg &edge, int x, int y, unsigned char lowThreshold);

void drawEdgesFromAnchor(int x, int y, const CImg &gradient,
                         const CImgFloat &direction, CImg &edge,
                         const bool isHorizontal);
void drawHorizontalEdgeFromAnchor(int x, int y, const CImg &gradient,
                                  const CImgFloat &direction, CImg &edge);
void drawVerticalEdgeFromAnchor(int x, int y, const CImg &gradient,
                                const CImgFloat &direction, CImg &edge);
CImg extractEdge(CImg &image);
CImg extractEdgeCanny(CImg &image, int method = 0);
CImg edgeDraw(CImg &image, int method = 0);

#endif