// CloudFront Function: URL 重写 (Viewer Request)
// 当前配置为 pass-through 模式
// API 路由已有独立的 /api/* Cache Behavior，无需在 Function 中重写
// 如需启用 URL 重写逻辑，取消下方注释
// 绑定 Behavior: Default (*)
// Runtime: cloudfront-js-2.0 (ECMAScript 5.1 兼容)

function handler(event) {
    var request = event.request;

    // Pass-through: 不做任何 URL 重写
    // CloudFront Cache Behaviors 已按路径模式正确路由:
    //   /api/*      -> ALB VPC Origin (各 API 独立 Behavior)
    //   /static/*   -> S3 Origin
    //   /images/*   -> S3 Origin
    //   /premium/*  -> S3 Origin (签名 URL)
    //   Default (*) -> ALB VPC Origin (SSR 页面)

    return request;
}
