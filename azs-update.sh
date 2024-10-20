#!/bin/bash

# 函数：显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -t <目标>      部署目标，格式：local 或 ip:password"
    echo "                 可以指定多个 -t 选项来部署到多个目标"
    echo "  -v <版本>      Docker镜像版本"
    echo "  -h             显示此帮助信息"
    echo "例子:"
    echo "  本地部署: $0 -t local -v 1.0.1"
    echo "  远程部署: $0 -t 192.168.1.100:password -v 1.0.1"
    echo "  多目标部署: $0 -t local -t 192.168.1.100:password -t 192.168.1.101:password -v 1.0.1"
    exit 0
}

# 初始化变量
TARGETS=()
VERSION=""

# 解析命令行参数
while getopts "t:v:h" opt; do
    case $opt in
        t) TARGETS+=("$OPTARG") ;;
        v) VERSION="$OPTARG" ;;
        h) show_help ;;
        \?) echo "错误: 无效的选项 -$OPTARG" >&2; exit 1 ;;
    esac
done

# 检查必要参数
if [ ${#TARGETS[@]} -eq 0 ] || [ -z "$VERSION" ]; then
    echo "错误: 必须提供至少一个目标 (-t) 和 Docker 版本 (-v)"
    show_help
fi

# 定义 Docker 命令函数
run_docker_commands() {
    local version="$1"
    echo "正在拉取 Docker 镜像 corton2233/azs-frontend:v$version ..."
    docker pull corton2233/azs-frontend:v$version || { echo "错误: 拉取镜像失败"; return 1; }

    echo "正在停止旧容器..."
    docker stop azs-frontend || echo "警告: 停止旧容器失败，可能不存在"

    echo "正在删除旧容器..."
    docker rm azs-frontend || echo "警告: 删除旧容器失败，可能不存在"

    echo "正在启动新容器..."
    docker run --name azs-frontend -p 3000:3000 -d corton2233/azs-frontend:v$version || { echo "错误: 启动新容器失败"; return 1; }

    echo "检查新容器是否成功运行..."
    docker ps | grep azs-frontend || { echo "错误: 新容器未能成功运行"; return 1; }

    echo "Docker 操作完成"
    return 0
}

# 部署到单个目标
deploy_to_target() {
    local target="$1"
    local version="$2"
    if [ "$target" = "local" ]; then
        echo "在本地执行 Docker 命令..."
        run_docker_commands "$version"
    else
        IFS=':' read -r ip password <<< "$target"
        echo "通过 SSH 在远程服务器 $ip 执行 Docker 命令..."
        sshpass -p "$password" ssh -o StrictHostKeyChecking=no root@$ip "$(typeset -f run_docker_commands); run_docker_commands $version"
    fi
    return $?
}

# 主要执行逻辑
for target in "${TARGETS[@]}"; do
    echo "开始部署到目标: $target"
    if deploy_to_target "$target" "$VERSION"; then
        echo "成功部署到目标: $target"
    else
        echo "部署到目标失败: $target"
    fi
    echo "----------------------------------------"
done

echo "所有部署操作完成"
