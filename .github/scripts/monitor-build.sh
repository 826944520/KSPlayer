#!/bin/bash
# KSPlayer GitHub Actions Build Monitor
# 监控流水线编译状态并报告问题

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
REPO_OWNER="826944520"
REPO_NAME="KSPlayer"
BRANCH="ios26-ffmpeg-upgrade"
CHECK_INTERVAL=30 # 秒

echo -e "${BLUE}📊 KSPlayer Build Monitor${NC}"
echo "Repository: $REPO_OWNER/$REPO_NAME"
echo "Branch: $BRANCH"
echo "Check interval: ${CHECK_INTERVAL}s"
echo ""

# 获取最新运行 ID
echo -e "${BLUE}🔍 Fetching latest workflow run...${NC}"

LATEST_RUN_URL="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/runs?branch=$BRANCH&per_page=1"

# 如果有 GitHub Token，添加到请求
if [ -n "$GITHUB_TOKEN" ]; then
    LATEST_RUN=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$LATEST_RUN_URL")
else
    LATEST_RUN=$(curl -s "$LATEST_RUN_URL")
fi

RUN_ID=$(echo "$LATEST_RUN" | jq -r '.workflow_runs[0].id')
RUN_STATUS=$(echo "$LATEST_RUN" | jq -r '.workflow_runs[0].status')
RUN_CONCLUSION=$(echo "$LATEST_RUN" | jq -r '.workflow_runs[0].conclusion')
RUN_URL=$(echo "$LATEST_RUN" | jq -r '.workflow_runs[0].html_url')

if [ "$RUN_ID" == "null" ]; then
    echo -e "${RED}❌ No workflow run found for branch $BRANCH${NC}"
    exit 1
fi

echo -e "${BLUE}✅ Workflow run found:${NC}"
echo "  ID: $RUN_ID"
echo "  Status: $RUN_STATUS"
echo "  Conclusion: $RUN_CONCLUSION"
echo "  URL: $RUN_URL"
echo ""

# 监控状态
echo -e "${BLUE}⏳ Monitoring build status...${NC}"
echo -e "Press Ctrl+C to stop monitoring"
echo ""

while true; do
    # 获取当前状态
    if [ -n "$GITHUB_TOKEN" ]; then
        RUN_STATUS=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/runs/$RUN_ID" \
            | jq -r '.status')
        RUN_CONCLUSION=$(curl -s -H "Authorization: token $GITHUB_TOKEN" \
            "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/runs/$RUN_ID" \
            | jq -r '.conclusion')
    else
        RUN_STATUS=$(curl -s \
            "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/runs/$RUN_ID" \
            | jq -r '.status')
        RUN_CONCLUSION=$(curl -s \
            "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/runs/$RUN_ID" \
            | jq -r '.conclusion')
    fi

    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

    # 显示状态
    case "$RUN_STATUS" in
        "queued")
            echo -e "[$TIMESTAMP] ${YELLOW}🔄 Queued${NC}"
            ;;
        "in_progress")
            echo -e "[$TIMESTAMP] ${YELLOW}🏗️  In Progress${NC}"
            ;;
        "completed")
            if [ "$RUN_CONCLUSION" == "success" ]; then
                echo -e "[$TIMESTAMP] ${GREEN}✅ Build Succeeded!${NC}"
                echo -e "${GREEN}🎉 All checks passed!${NC}"
                exit 0
            elif [ "$RUN_CONCLUSION" == "failure" ]; then
                echo -e "[$TIMESTAMP] ${RED}❌ Build Failed!${NC}"
                echo -e "${RED}🔗 View details: $RUN_URL${NC}"

                # 获取失败日志
                echo ""
                echo -e "${RED}📋 Fetching error logs...${NC}"
                fetch_error_logs "$RUN_ID"
                exit 1
            elif [ "$RUN_CONCLUSION" == "cancelled" ]; then
                echo -e "[$TIMESTAMP] ${YELLOW}⚠️  Build Cancelled${NC}"
                exit 1
            else
                echo -e "[$TIMESTAMP] ${YELLOW}⚠️  Build $RUN_CONCLUSION${NC}"
                exit 1
            fi
            ;;
        *)
            echo -e "[$TIMESTAMP] ${RED}❓ Unknown status: $RUN_STATUS${NC}"
            ;;
    esac

    # 等待下一次检查
    sleep $CHECK_INTERVAL
done

# 获取错误日志
fetch_error_logs() {
    local RUN_ID=$1
    local JOBS_URL="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/runs/$RUN_ID/jobs"

    if [ -n "$GITHUB_TOKEN" ]; then
        JOBS=$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$JOBS_URL")
    else
        JOBS=$(curl -s "$JOBS_URL")
    fi

    echo ""
    echo -e "${RED}=== Failed Jobs ===${NC}"

    echo "$JOBS" | jq -r '.jobs[] | select(.conclusion == "failure") | "\(.name): \(.conclusion)"'

    echo ""
    echo -e "${RED}=== Recent Build Errors (last 50 lines) ===${NC}"

    # 获取最后一个失败的 job 的日志
    FAILED_JOB_ID=$(echo "$JOBS" | jq -r '.jobs[] | select(.conclusion == "failure") | .id' | head -1)

    if [ -n "$FAILED_JOB_ID" ]; then
        LOGS_URL="https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/actions/jobs/$FAILED_JOB_ID/logs"

        if [ -n "$GITHUB_TOKEN" ]; then
            LOGS=$(curl -s -L -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3+json" "$LOGS_URL")
        else
            # 匿名用户需要下载 zip
            echo -e "${YELLOW}⚠️  Anonymous access limited. Please set GITHUB_TOKEN for full logs${NC}"
            return
        fi

        # 显示错误相关行
        echo "$LOGS" | grep -i "error\|failed\|exception" | tail -50
    fi
}