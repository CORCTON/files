#!/bin/bash

# 函数：显示帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo "选项:"
    echo "  -t <目标>      部署目标，格式：local 或 username:ip:password"
    echo "                 可以指定多个 -t 选项来部署到多个目标"
    echo "  -v <版本>      Docker镜像版本"
    echo "  -d <用户名>    Docker Hub 用户名（可选，用于远程部署）"
    echo "  -p <密码>      Docker Hub 密码（可选，用于远程部署）"
    echo "  -h             显示此帮助信息"
    echo "例子:"
    echo "  本地部署: $0 -t local -v 1.0.1"
    echo "  远程部署: $0 -t root:192.168.1.100:password -v 1.0.1 -d dockeruser -p dockerpass"
    echo "  多目标部署: $0 -t local -t root:192.168.1.100:password -t admin:192.168.1.101:password -v 1.0.1 -d dockeruser -p dockerpass"
    exit 0
}

# 初始化变量
TARGETS=()
VERSION=""
DOCKER_USER=""
DOCKER_PASS=""

# 解析命令行参数
while getopts "t:v:d:p:h" opt; do
    case $opt in
        t) TARGETS+=("$OPTARG") ;;
        v) VERSION="$OPTARG" ;;
        d) DOCKER_USER="$OPTARG" ;;
        p) DOCKER_PASS="$OPTARG" ;;
        h) show_help ;;
        \?) echo "错误: 无效的选项 -$OPTARG" >&2; exit 1 ;;
    esac
done

# 检查必要参数
if [ ${#TARGETS[@]} -eq 0 ] || [ -z "$VERSION" ]; then
    echo "错误: 必须提供至少一个目标 (-t) 和 Docker 版本 (-v)"
    show_help
fi

# 定义本地 Docker 登录函数
local_docker_login() {
    local version="$1"
    echo "尝试拉取镜像 corton2233/azs-frontend:v$version..."
    if ! docker pull "corton2233/azs-frontend:v$version"; then
        echo "拉取失败。需要登录 Docker Hub。"
        read -p "请输入 Docker Hub 用户名: " docker_user
        read -s -p "请输入 Docker Hub 密码: " docker_pass
        echo
        if ! echo "$docker_pass" | docker login -u "$docker_user" --password-stdin; then
            echo "错误: Docker 登录失败"
            return 1
        fi
        echo "Docker 登录成功"
        if ! docker pull "corton2233/azs-frontend:v$version"; then
            echo "错误: 登录后仍然无法拉取镜像"
            return 1
        fi
    fi
    return 0
}

# 定义远程 Docker 登录函数
remote_docker_login() {
    local version="$1"
    local docker_user="$2"
    local docker_pass="$3"
    
    echo "尝试拉取镜像 corton2233/azs-frontend:v$version..."
    if ! docker pull "corton2233/azs-frontend:v$version"; then
        if [ -z "$docker_user" ] || [ -z "$docker_pass" ]; then
            echo "错误: 远程 Docker 登录失败。请提供 Docker Hub 凭据。"
            return 1
        fi
        echo "尝试 Docker 登录..."
        if ! echo "$docker_pass" | docker login -u "$docker_user" --password-stdin; then
            echo "错误: Docker 登录失败"
            return 1
        fi
        echo "Docker 登录成功"
        if ! docker pull "corton2233/azs-frontend:v$version"; then
            echo "错误: 登录后仍然无法拉取镜像"
            return 1
        fi
    fi
    return 0
}

# 定义 Docker 命令函数
run_docker_commands() {
    local version="$1"
    local is_remote="$2"
    local docker_user="$3"
    local docker_pass="$4"

    if [ "$is_remote" = "true" ]; then
        if ! remote_docker_login "$version" "$docker_user" "$docker_pass"; then
            return 1
        fi
    else
        if ! local_docker_login "$version"; then
            return 1
        fi
    fi

    echo "正在停止旧容器..."
    docker stop azs-frontend || echo "警告: 停止旧容器失败，可能不存在"

    echo "正在删除旧容器..."
    docker rm azs-frontend || echo "警告: 删除旧容器失败，可能不存在"

    echo "正在启动新容器..."
    if ! docker run --name azs-frontend -p 3000:3000 -d "corton2233/azs-frontend:v$version"; then
        echo "错误: 启动新容器失败"
        return 1
    fi

    echo "检查新容器是否成功运行..."
    if ! docker ps | grep azs-frontend; then
        echo "错误: 新容器未能成功运行"
        return 1
    fi

    echo "Docker 操作完成"
    return 0
}

# 部署到单个目标
deploy_to_target() {
    local target="$1"
    local version="$2"
    local docker_user="$3"
    local docker_pass="$4"

    if [ "$target" = "local" ]; then
        echo "在本地执行 Docker 命令..."
        run_docker_commands "$version" "false"
    else
        IFS=':' read -r username ip password <<< "$target"
        echo "通过 SSH 在远程服务器 $ip 以用户 $username 身份执行 Docker 命令..."
        sshpass -p "$password" ssh -o StrictHostKeyChecking=no "$username@$ip" "$(typeset -f remote_docker_login run_docker_commands); run_docker_commands '$version' 'true' '$docker_user' '$docker_pass'"
    fi
    return $?
}

# 主要执行逻辑
for target in "${TARGETS[@]}"; do
    echo "开始部署到目标: $target"
    if deploy_to_target "$target" "$VERSION" "$DOCKER_USER" "$DOCKER_PASS"; then
        echo "成功部署到目标: $target"
    else
        echo "部署到目标失败: $target"
    fi
    echo "----------------------------------------"
done

echo "所有部署操作完成"
