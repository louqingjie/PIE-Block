# -*- coding: utf-8 -*-
r"""PieBlock 编译服务管理后台（Streamlit）。

启动（局域网可访问）：
    .\.venv\Scripts\streamlit run keil_server\admin_panel.py --server.address 0.0.0.0 --server.port 8501

只监听内网/本机，不接公网隧道，避免扩大攻击面。
"""
from __future__ import annotations

import time
from datetime import datetime

import httpx
import pandas as pd
import streamlit as st

st.set_page_config(page_title="PieBlock 编译服务管理后台", layout="wide")

SERVER_URL = st.sidebar.text_input("服务器地址", value="http://127.0.0.1:8000")
ADMIN_KEY = st.sidebar.text_input("管理员 Key", type="password")
BASE = SERVER_URL.rstrip("/")


def api_headers() -> dict:
    return {"Authorization": f"Bearer {ADMIN_KEY}"}


def api_request(method: str, path: str, **kw) -> dict | None:
    try:
        r = httpx.request(method, f"{BASE}{path}", headers=api_headers(), timeout=20, **kw)
    except httpx.HTTPError as e:
        st.error(f"无法连接服务器：{e}")
        return None
    if r.status_code == 401:
        st.error("管理员 Key 无效，请检查左侧输入")
        return None
    if r.status_code != 200:
        try:
            detail = r.json().get("detail", r.text)
        except Exception:
            detail = r.text
        st.error(f"接口错误 {r.status_code}: {detail}")
        return None
    return r.json()


def fmt_ts(ts) -> str:
    try:
        return datetime.fromtimestamp(float(ts)).strftime("%Y-%m-%d %H:%M")
    except (TypeError, ValueError):
        return "-"


if not ADMIN_KEY:
    st.info("在左侧输入管理员 Key 登录后使用")
    st.stop()

usage = api_request("GET", "/usage")
if usage is None:
    st.stop()

st.sidebar.success("已登录")

tab_usage, tab_keys, tab_tasks = st.tabs(["用量统计", "用户 Key 管理", "编译任务"])

# ---------------------------------------------------------------- 用量统计
with tab_usage:
    users = usage.get("users", {})
    total_today = sum(u["today"] for u in users.values())
    total_all = sum(u["total"] for u in users.values())
    health = api_request("GET", "/health") or {}
    rate_min = health.get("config", {}).get("rate_limit_per_minute", "-")
    rate_day = health.get("config", {}).get("rate_limit_per_day", "-")
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("今日编译次数", total_today)
    c2.metric("累计编译次数", total_all)
    c3.metric("每分钟限速", f"{rate_min} 次")
    c4.metric("单日上限", f"{rate_day} 次")

    # 近 7 天总编译量柱状图
    dates = sorted({d for u in users.values() for d in u["last7"]})
    if dates:
        df = pd.DataFrame(
            {d: sum(u["last7"].get(d, 0) for u in users.values()) for d in dates},
            index=["编译次数"],
        ).T
        df.index.name = "日期"
        st.subheader("近 7 天编译量")
        st.bar_chart(df, height=300)

    st.subheader("各用户用量")
    rows = [
        {
            "用户": u,
            "今日": v["today"],
            "累计": v["total"],
            "近7天": sum(v["last7"].values()),
        }
        for u, v in users.items()
    ]
    if rows:
        st.dataframe(pd.DataFrame(rows), width="stretch", hide_index=True)
    else:
        st.caption("暂无编译记录")

# ---------------------------------------------------------------- 用户 Key 管理
with tab_keys:
    st.subheader("添加用户")
    col_name, col_btn = st.columns([3, 1])
    new_user = col_name.text_input("用户名", key="new_user", label_visibility="collapsed",
                                   placeholder="输入用户名，如 张三")
    if col_btn.button("生成 Key", type="primary", width="stretch"):
        if not new_user.strip():
            st.warning("请输入用户名")
        else:
            r = api_request("POST", "/keys", json={"user": new_user.strip()})
            if r is not None:
                st.success(f"已为用户 {r['user']} 生成 Key")
                st.code(r["key"], language=None)
                st.caption("复制并私下发给该用户（只显示一次）")

    st.subheader("用户列表")
    r = api_request("GET", "/keys")
    if r is not None:
        user_rows = []
        for u in r.get("users", []):
            created = max(
                (k.get("created_at") or 0 for k in u["keys"]), default=0,
            )
            user_rows.append({
                "用户": u["user"],
                "Key 数": u["key_count"],
                "最近创建": fmt_ts(created),
                "启用": all(k["enabled"] for k in u["keys"]),
            })
        if user_rows:
            st.dataframe(pd.DataFrame(user_rows), width="stretch", hide_index=True)
        else:
            st.caption("暂无用户，点上方「生成 Key」添加")

        col_sel, col_rev = st.columns([3, 1])
        rev_user = col_sel.selectbox(
            "选择要吊销的用户", [u["user"] for u in r.get("users", [])],
            key="rev_user",
        )
        if col_rev.button("吊销该用户全部 Key", type="secondary", width="stretch"):
            rr = api_request("DELETE", f"/keys/{rev_user}")
            if rr is not None:
                st.success(f"已吊销 {rr['revoked']}（{rr['count']} 个 Key）")
                st.rerun()

# ---------------------------------------------------------------- 编译任务
with tab_tasks:
    col_refresh = st.columns(1)[0]
    if col_refresh.button("刷新任务列表", width="stretch"):
        st.rerun()
    r = api_request("GET", "/tasks", params={"limit": 50})
    if r is None:
        st.stop()
    tasks = r.get("tasks", [])
    if not tasks:
        st.caption("暂无任务")
        st.stop()
    task_rows = [
        {
            "任务 ID": t["task_id"],
            "状态": t["status"],
            "用户": t["user"] or "-",
            "提交时间": fmt_ts(t["created_at"]),
            "完成时间": fmt_ts(t["finished_at"]) if t["finished_at"] else "-",
            "hex (KB)": round(t["hex_size"] / 1024, 1) if t["hex_size"] else 0,
            "错误": (t.get("error") or "")[:60],
        }
        for t in tasks
    ]
    st.dataframe(pd.DataFrame(task_rows), width="stretch", hide_index=True)
