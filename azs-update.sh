#!/bin/bash

# 函数：显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -i <IP>        服务器IP地址（本地运行时不需要）"
    echo "  -p <密码>      SSH密码（本地运行时不需要）"
    echo "  -v <版本>      Docker镜像版本"
    echo "  -s             在本地运行（不使用SSH）"
    echo "  -h             显示此帮助信息"
    exit 0
}

# 初始化变量
IP=""
PASSWORD=""
VERSION=""
LOCAL_RUN=false

# 解析命令行参数
while getopts "i:p:v:sh" opt; do
    case $opt in
        i) IP="$OPTARG" ;;
        p) PASSWORD="$OPTARG" ;;
        v) VERSION="$OPTARG" ;;
        s) LOCAL_RUN=true ;;
        h) show_help ;;
        \?) echo "错误: 无效的选项 -$OPTARG" >&2; exit 1 ;;
    esac
done

# 检查必要参数
if [ "$LOCAL_RUN" = false ] && ([ -z "$IP" ] || [ -z "$PASSWORD" ]); then
    echo "错误: 远程运行时需要提供 IP 和密码"
    show_help
fi

if [ -z "$VERSION" ]; then
    echo "错误: 必须提供 Docker 版本"
    show_help
fi

# 定义 Docker 命令函数
run_docker_commands() {
    echo "正在拉取 Docker 镜像..."
    docker pull corton2233/azs-frontend:v$VERSION || { echo "错误: 拉取镜像失败"; exit 1; }

    echo "正在停止旧容器..."
    docker stop azs-frontend || echo "警告: 停止旧容器失败，可能不存在"

    echo "正在删除旧容器..."
    docker rm azs-frontend || echo "警告: 删除旧容器失败，可能不存在"

    echo "正在启动新容器..."
    docker run --name azs-frontend -p 3000:3000 -d corton2233/azs-frontend:v$VERSION || { echo "错误: 启动新容器失败"; exit 1; }

    echo "检查新容器是否成功运行..."
    docker ps | grep azs-frontend || { echo "错误: 新容器未能成功运行"; exit 1; }

    echo "Docker 操作完成"
}

# 主要执行逻辑
if [ "$LOCAL_RUN" = true ]; then
    echo "在本地执行 Docker 命令..."
    run_docker_commands
else
    echo "通过 SSH 在远程服务器执行 Docker 命令..."
    echo "目标服务器 IP: $IP"
    echo "Docker 版本: $VERSION"

    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no root@$IP "$(typeset -f run_docker_commands); run_docker_commands"
    if [ $? -ne 0 ]; then
        echo "错误: 远程操作失败"
        exit 1
    fi
fi

echo "更新过程完成"