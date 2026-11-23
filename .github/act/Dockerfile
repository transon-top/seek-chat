# 本地 act 镜像：catthehacker act 变体缺 clang，补上以对齐真实 ubuntu-24.04 runner。
# 构建：docker build --platform linux/amd64 -t seekchat-act-24.04 .github/act
FROM catthehacker/ubuntu:act-24.04

RUN apt-get update \
 && apt-get install -y --no-install-recommends clang \
 && rm -rf /var/lib/apt/lists/*
