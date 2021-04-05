gst-launch-1.0 filesrc location=out.h264 ! video/x-h264 ! h264parse ! avdec_h264 ! videoconvert ! videorate ! video/x-raw,framerate=30/1 ! autovideosink
