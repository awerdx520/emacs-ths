# 技术债

## 2026-10-22 — 东财 push2 域名族在本机不可达，A 股成交明细失效、A 股榜单依赖新浪回退

- **现象**：`push2`、`push2his`、`82.push2`、`88.push2`、`push2delay` 在本机（WSL2 mirrored 网络）TLS 握手后 EOF；57 次尝试仅 2 次偶发 200。
- **影响**：① A 股成交明细（唯一东财源）功能失效；② A 股排行榜依赖 `ths-data-ranking-providers` 的新浪回退才能出数据；③ 港美股东财报价 / 日 K 分支无法实网验证，只能靠离线 fixture 覆盖。
- **复现**：`curl -sv --noproxy '*' --max-time 5 'https://push2.eastmoney.com/api/qt/stock/get?secid=1.600519&fields=f43'`（预期 TLS 握手后 EOF）。
- **发现日期**：2026-10-22（两轮港美股接口探测期间）。
- **处置**：港美支持计划不复现该父问题（A 股成交明细行为保持原状）；恢复可达性后补测港美东财分支，并把 `make live-check` 里的 `skip` 改回真实检查。
