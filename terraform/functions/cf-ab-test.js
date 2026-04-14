// CloudFront Function: A/B 测试分流 (Viewer Request)
// 读取 x-ab-group cookie，无则随机分配 A/B 组
// 将分组信息通过 header 传递给源站
// 绑定 Behavior: Default (*)
// Runtime: cloudfront-js-2.0 (ECMAScript 5.1 兼容)
//
// 工作流:
//   1. 检查 x-ab-group cookie
//   2. 若缺失 -> Math.random() 分配 A (50%) 或 B (50%)
//   3. 将分组写入请求 cookie（ORP 转发到源站）
//   4. 添加 X-AB-Group header（源站可直接读取）
//   5. 若为新分配，添加 x-ab-new-assignment header 通知源站设置 Set-Cookie

function handler(event) {
    var request = event.request;
    var cookies = request.cookies;
    var abGroup;

    // 检查是否已有 A/B 分组 cookie
    if (cookies['x-ab-group'] && cookies['x-ab-group'].value) {
        // 已有分组 — 验证值合法性
        var existing = cookies['x-ab-group'].value;
        if (existing === 'A' || existing === 'B') {
            abGroup = existing;
        } else {
            // cookie 值非法，重新分配
            abGroup = (Math.random() < 0.5) ? 'A' : 'B';
            request.cookies['x-ab-group'] = { value: abGroup };
            request.headers['x-ab-new-assignment'] = { value: 'true' };
        }
    } else {
        // 新用户 — 随机分配 A 或 B 组（50/50 概率）
        abGroup = (Math.random() < 0.5) ? 'A' : 'B';

        // 将 cookie 写入请求（通过 Origin Request Policy 转发到源站）
        request.cookies['x-ab-group'] = { value: abGroup };

        // 标记为新分配，源站据此在响应中设置 Set-Cookie 持久化
        request.headers['x-ab-new-assignment'] = { value: 'true' };
    }

    // 添加 X-AB-Group header 供源站使用
    // 比从 cookie 读取更可靠（header 不受 cookie 解析影响）
    request.headers['x-ab-group'] = { value: abGroup };

    return request;
}
