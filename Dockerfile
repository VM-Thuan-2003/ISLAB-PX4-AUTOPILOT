# Ubuntu 22.04 + ROS 2 Humble + Gazebo Classic + ISLAB PX4 ROS 2 + Micro XRCE-DDS Agent
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
SHELL ["/bin/bash", "-c"]

# ---------- Base tools, enable universe, locale ----------
RUN apt-get update && apt-get install -y --no-install-recommends \
    software-properties-common \
 && add-apt-repository -y universe \
 && apt-get update && apt-get install -y --no-install-recommends \
    locales curl gnupg2 lsb-release ca-certificates \
    build-essential git python3-pip \
    cmake ninja-build pkg-config \
    bash-completion less vim \
 && rm -rf /var/lib/apt/lists/*
RUN locale-gen en_US en_US.UTF-8 && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8
ENV LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

# ---------- Add ROS 2 apt repo ----------
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc \
 | gpg --dearmor -o /usr/share/keyrings/ros-archive-keyring.gpg && \
 echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" \
 > /etc/apt/sources.list.d/ros2.list

# Choose ROS bundle: ros-humble-desktop (default) | ros-humble-ros-base
ARG ROS_PKG=ros-humble-desktop
ENV ROS_DISTRO=humble

# ---------- Install ROS 2 + dev tools + Gazebo Classic ----------
RUN apt-get update && apt-get install -y --no-install-recommends \
    ${ROS_PKG} \
    python3-colcon-common-extensions python3-rosdep ros-dev-tools \
    gazebo libgazebo-dev \
    ros-humble-gazebo-ros ros-humble-gazebo-ros-pkgs \
    ros-humble-image-transport ros-humble-camera-info-manager \
    ros-humble-cv-bridge ros-humble-sensor-msgs ros-humble-image-pipeline \
    ros-humble-rqt-image-view ros-humble-rviz2 \
    ros-humble-rmw-fastrtps-cpp \
 && rm -rf /var/lib/apt/lists/*

# ---------- Ensure ABI-compatible NumPy/OpenCV (avoid pip numpy 2.x) ----------
RUN apt-get update && apt-get install -y --no-install-recommends \
      python3-opencv python3-numpy \
    && rm -rf /var/lib/apt/lists/* \
 && python3 -m pip uninstall -y numpy || true \
 && rm -rf /usr/local/lib/python3.10/dist-packages/numpy* /root/.local/lib/python3.10/site-packages/numpy* || true \
 && apt-mark hold python3-numpy

# ---------- Python packages for ROS TF ----------
# Prefer ROS deb; if unavailable, fall back to GitHub (locusrobotics)
RUN apt-get update && \
    (apt-get install -y --no-install-recommends ros-humble-tf-transformations || \
     pip3 install --no-cache-dir git+https://github.com/locusrobotics/tf_transformations@1.0.0) && \
    rm -rf /var/lib/apt/lists/*

# Optional helper math lib
RUN pip3 install --no-cache-dir transforms3d

# ---------- rosdep init ----------
RUN rosdep init || true && rosdep update

# ---------- vcstool (via pip) ----------
RUN pip3 install --no-cache-dir vcstool

# ---------- Auto-source ROS + entrypoint ----------
RUN echo 'source /opt/ros/humble/setup.bash' >> /etc/bash.bashrc && \
    printf '#!/bin/bash\nsource /opt/ros/humble/setup.bash\nexec "$@"\n' > /ros_entrypoint.sh && \
    chmod +x /ros_entrypoint.sh

# ---------- Install eProsima Micro XRCE-DDS Agent ----------
# Agent needs asio & tinyxml2
RUN apt-get update && apt-get install -y --no-install-recommends \
      libasio-dev libtinyxml2-dev \
    && rm -rf /var/lib/apt/lists/*
ARG XRCE_AGENT_REPO=https://github.com/eProsima/Micro-XRCE-DDS-Agent.git
RUN git clone --depth 1 ${XRCE_AGENT_REPO} /opt/micro-xrce-dds-agent && \
    cmake -S /opt/micro-xrce-dds-agent -B /opt/micro-xrce-dds-agent/build \
          -DCMAKE_BUILD_TYPE=Release && \
    cmake --build /opt/micro-xrce-dds-agent/build -j"$(nproc)" && \
    cmake --install /opt/micro-xrce-dds-agent/build && \
    ldconfig
# Handy alias: UDP agent on 8888
RUN echo "alias fast_dds='MicroXRCEAgent udp4 -p 8888'" >> /etc/bash.bashrc

# ---------- Clone & build your ISLAB PX4 ROS 2 workspace ----------
WORKDIR /root
RUN git clone --recurse-submodules --branch main https://github.com/VM-Thuan-2003/ISLAB-PX4-AUTOPILOT.git

# PX4 deps script (handle both possible locations; skip if missing)
WORKDIR /root/ISLAB-PX4-AUTOPILOT/islab_autopilot
RUN bash Tools/setup/ubuntu.sh

WORKDIR /root/ISLAB-PX4-AUTOPILOT/islab_px4
RUN source /opt/ros/humble/setup.bash && \
    rosdep install -y --from-paths src --ignore-src --rosdistro humble && \
    colcon build --symlink-install

RUN python3 -m pip uninstall -y numpy opencv-python opencv-contrib-python || true
RUN rm -rf /usr/local/lib/python3.10/dist-packages/numpy* \
    /usr/local/lib/python3.10/dist-packages/cv2* \
    /root/.local/lib/python3.10/site-packages/numpy* \
    /root/.local/lib/python3.10/site-packages/cv2* 2>/dev/null || true

RUN apt-get update
RUN apt-get install -y --no-install-recommends python3-numpy python3-opencv python3-numpy-dev
RUN apt-mark hold python3-numpy

# ---------- Auto-source workspace ----------
RUN echo 'source /root/ISLAB-PX4-AUTOPILOT/islab_px4/install/setup.bash' >> /etc/bash.bashrc

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
