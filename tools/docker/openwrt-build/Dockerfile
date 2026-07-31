FROM ubuntu:24.04@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		bash \
		binutils \
		bison \
		build-essential \
		bzip2 \
		ca-certificates \
		ccache \
		clang \
		curl \
		file \
		flex \
		g++ \
		gawk \
		gcc-multilib \
		gettext \
		git \
		libelf-dev \
		libncurses-dev \
		libssl-dev \
		lz4 \
		make \
		patch \
		perl \
		pkg-config \
		python3 \
		python3-pyelftools \
		python3-setuptools \
		qemu-utils \
		rsync \
		swig \
		tar \
		unzip \
		wget \
		which \
		xsltproc \
		zlib1g-dev \
		zstd \
	&& rm -rf /var/lib/apt/lists/*

USER ubuntu
WORKDIR /workspace

ENV CCACHE_DIR=/workspace/.ccache

CMD ["bash"]
