#define vpx_codec_enc_cfg vpx_codec_enc_cfg_ctx_forward
#define vpx_codec_dec_cfg vpx_codec_dec_cfg_ctx_forward
#include <vpx/vpx_codec.h>
#undef vpx_codec_enc_cfg
#undef vpx_codec_dec_cfg

#include <vpx/vp8cx.h>
#include <vpx/vp8dx.h>
#include <vpx/vpx_encoder.h>
#include <vpx/vpx_decoder.h>
#include <vpx/vp8.h>
#include <vpx/vpx_frame_buffer.h>
#include <vpx/vpx_image.h>
#include <vpx/vpx_integer.h>
