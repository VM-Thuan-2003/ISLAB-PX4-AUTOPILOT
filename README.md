# islab_contest

```
git submodule update --init --recursive
```


- Command run in terminal:
```
xhost +local:docker
docker run -it --rm \
  --net=host \
  --gpus all \
  -e DISPLAY \
  -e QT_X11_NO_MITSHM=1 \
  -e NVIDIA_DRIVER_CAPABILITIES=all \
  -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
  --name islab_px4_autopilot_run \
  vmthuan16052003/islab_px4_autopilot:latest
```