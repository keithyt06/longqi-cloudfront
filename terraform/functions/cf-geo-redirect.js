// CloudFront Function: 地理位置重定向 (Viewer Request)
// 读取 CloudFront-Viewer-Country header，CN 用户重定向到 /cn/ 前缀
// 排除 /api/ /static/ /images/ 路径，避免影响 API 和静态资源
// 绑定 Behavior: Default (*)
// Runtime: cloudfront-js-2.0 (ECMAScript 5.1 兼容)
//
// 前提条件:
//   Origin Request Policy 必须包含 CloudFront-Viewer-Country header
//   （allViewerAndWhitelistCloudFront 行为自动包含）

function handler(event) {
    var request = event.request;
    var uri = request.uri;
    var headers = request.headers;

    // 排除路径 — 这些路径不做地理重定向
    var excludePrefixes = ['/api/', '/static/', '/images/', '/cn/', '/premium/'];
    for (var i = 0; i < excludePrefixes.length; i++) {
        if (uri.indexOf(excludePrefixes[i]) === 0) {
            return request;
        }
    }

    // 排除根路径 /cn（不带斜杠的情况）
    if (uri === '/cn') {
        return request;
    }

    // 读取 CloudFront 注入的国家代码 header
    var countryHeader = headers['cloudfront-viewer-country'];
    if (!countryHeader || !countryHeader.value) {
        // 无国家信息 — 不做处理
        return request;
    }

    var country = countryHeader.value.toUpperCase();

    // CN（中国大陆）用户 — 302 重定向到 /cn/ 前缀路径
    if (country === 'CN') {
        var redirectUri = '/cn' + uri;
        // 保留 query string
        var qs = request.querystring;
        var qsStr = '';
        var keys = Object.keys(qs);
        if (keys.length > 0) {
            var pairs = [];
            for (var j = 0; j < keys.length; j++) {
                var key = keys[j];
                var val = qs[key];
                if (val.multiValue) {
                    for (var k = 0; k < val.multiValue.length; k++) {
                        pairs.push(key + '=' + val.multiValue[k].value);
                    }
                } else {
                    pairs.push(key + '=' + val.value);
                }
            }
            qsStr = '?' + pairs.join('&');
        }

        var response = {
            statusCode: 302,
            statusDescription: 'Found',
            headers: {
                'location': { value: redirectUri + qsStr },
                'cache-control': { value: 'no-store, no-cache' }
            }
        };
        return response;
    }

    return request;
}
