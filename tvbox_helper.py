import os
import base64
import json
import re
import requests
import zlib
import gzip
import zipfile
import io
import urllib.parse
import urllib3
import binascii
import shutil
import hashlib
import concurrent.futures
import webbrowser
import random
from datetime import datetime, timezone, timedelta

# 禁用urllib3的HTTPS证书警告
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

# 尝试导入高阶 TLS 指纹模拟库
try:
    from curl_cffi import requests as cffi_requests
    HAS_CFFI = True
except ImportError:
    HAS_CFFI = False

# 全局自适应配置
RUNTIME_PATCH_CONFIG = {
    "force_redownload": True,
    "enable_cffi_fingerprint": True,
    "bypass_anti_crawler": True,
    "auto_verify_sources": True
}

# 干净精准的反链、关键词及失效/更换地址到真实多仓直链的映射表
KNOWN_ANTI_LINK_MAPPING = {
    "天神": "https://gh-proxy.com/https://raw.githubusercontent.com/wxrjck/-YSC-/main/jh.txt",
    "14505.kstore.space/天神IY.json": "https://gh-proxy.com/https://raw.githubusercontent.com/wxrjck/-YSC-/main/jh.txt",
    "无意云": "https://gh-proxy.com/https://raw.githubusercontent.com/wxrjck/-YSC-/main/jh.txt",
    "wuyiyun": "https://gh-proxy.com/https://raw.githubusercontent.com/wxrjck/-YSC-/main/jh.txt"
}

def pack_sources_files_zip():
    sources_base = os.path.normpath("./sources_files")
    if not os.path.exists(sources_base):
        print(f"⚠️ [打包提示] 未找到 {sources_base} 文件夹，跳过 ZIP 打包。")
        return False
    
    try:
        with zipfile.ZipFile("sources_files.zip", 'w', zipfile.ZIP_DEFLATED) as zipf:
            for root, dirs, files in os.walk(sources_base):
                for file in files:
                    full_path = os.path.join(root, file)
                    rel_path = os.path.relpath(full_path, start=os.path.dirname(sources_base))
                    zipf.write(full_path, rel_path)
        
        shutil.copy("sources_files.zip", "folder_only.zip")

        report_path = os.path.abspath("audit_report.html")
        if os.path.exists(report_path):
            with zipfile.ZipFile("audit_report.zip", 'w', zipfile.ZIP_DEFLATED) as zipf:
                zipf.write(report_path, "audit_report.html")

        print(f"✅ 资源压缩包已成功生成：sources_files.zip, folder_only.zip, audit_report.zip")
        return True
    except Exception as e:
        print(f"❌ 打包 ZIP 压缩包异常: {e}")
        return False

def pack_audit_report_zip():
    report_path = os.path.abspath("audit_report.html")
    if os.path.exists(report_path):
        try:
            with zipfile.ZipFile("audit_report.zip", 'w', zipfile.ZIP_DEFLATED) as zipf:
                zipf.write(report_path, "audit_report.html")
            print(f"✅ 审计报告压缩包已成功生成：audit_report.zip")
            return True
        except Exception as e:
            print(f"❌ 打包 audit_report.zip 异常: {e}")
    return False

def apply_runtime_patch(target_menu_name):
    RUNTIME_PATCH_CONFIG["force_redownload"] = True
    RUNTIME_PATCH_CONFIG["bypass_anti_crawler"] = True
    print(f"  -> 🛠️ [自适应热修引擎] 已根据 [{target_menu_name}] 最新逻辑完成运行时核心下载管线的实时修正！")

def select_or_input_folder(require_api_converted=False):
    sources_base = os.path.normpath("./sources_files")
    os.makedirs(sources_base, exist_ok=True)
    
    folders = []
    for f in os.listdir(sources_base):
        f_path = os.path.join(sources_base, f)
        if os.path.isdir(f_path):
            if require_api_converted:
                has_config = any(file.lower().endswith(('.json', '.txt')) for file in os.listdir(f_path))
                if has_config:
                    folders.append(f)
            else:
                folders.append(f)
                
    if folders:
        print("\n📁 可用的分类文件夹:")
        for idx, f in enumerate(folders, 1):
            print(f"  [{idx}] {f}")
        print(f"  [0] 手动输入新文件夹名称")
        print(f"  [b] 返回上级菜单")
        
        choice = input("请选择编号、输入 0 或按 b 返回: ").strip().lower()
        if choice == 'b':
            return None
        if choice.isdigit() and 1 <= int(choice) <= len(folders):
            selected = folders[int(choice) - 1]
            print(f"-> 已选择文件夹: {selected}")
            return selected
    else:
        print(f"  [b] 返回上级菜单")
            
    folder_name = input("请输入分类文件夹名称 (输入 b 返回): ").strip()
    if folder_name.lower() == 'b':
        return None
    return folder_name if folder_name else "default_sources"

def download_file(url, save_path, base_url=None, force_redownload=False):
    if not url or not isinstance(url, str):
        return False, "无效的 URL 链接"
    
    url = url.strip().replace(" ", "")
    
    if "127.0.0.1" in url or "localhost" in url:
        return False, "本地回环地址，跳过下载"
    
    if base_url and not url.startswith("http://") and not url.startswith("https://"):
        url = urllib.parse.urljoin(base_url, url)
        
    if not (url.startswith("http://") or url.startswith("https://")):
        return False, f"非标准网络协议: {url}"

    urls_to_try = []
    if url.lower().endswith('.php') and '?.jar' not in url:
        urls_to_try.append(url + "?.jar")
        urls_to_try.append(url + "&jar=1")
    urls_to_try.append(url)
    clean_download_url = url.split('?')[0] if '?' in url else url
    if clean_download_url not in urls_to_try:
        urls_to_try.append(clean_download_url)

    if "https://" in clean_download_url and any(k in clean_download_url for k in ['vicp.fun', 'cpolar', 'natapp', 'f3322', 'ticp', '47.120']):
        urls_to_try.insert(0, clean_download_url.replace("https://", "http://"))

    no_proxy_dict = {}
    os.environ['http_proxy'] = ''
    os.environ['https_proxy'] = ''
    os.environ['HTTP_PROXY'] = ''
    os.environ['HTTPS_PROXY'] = ''
    os.environ['NO_PROXY'] = '*'

    last_err = ""

    for current_url in urls_to_try:
        current_url = current_url.strip().replace(" ", "")
        try:
            os.makedirs(os.path.dirname(save_path), exist_ok=True)
            print(f"📥 正在免代理专线下载: {current_url}")
            
            parsed_url = urllib.parse.urlparse(current_url)
            base_root = f"{parsed_url.scheme}://{parsed_url.netloc}"
            
            headers_list = [
                {
                    "User-Agent": "TVBox/android (Build/11; TV)",
                    "X-Requested-With": "com.github.tvbox.osc",
                    "Referer": base_root + "/",
                    "Accept": "*/*",
                    "Accept-Encoding": "identity"
                },
                {
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
                    "Referer": base_root + "/",
                    "Accept": "*/*"
                }
            ]
            
            for headers in headers_list:
                try:
                    res = requests.get(current_url, headers=headers, verify=False, timeout=30, proxies=no_proxy_dict, stream=True)
                    if res.status_code == 200:
                        content = res.content
                        if b'<html' in content[:100].lower() and b'</html>' in content.lower():
                            last_err = f"服务器返回了 HTML 拦截/错误页面 ({current_url})"
                            continue
                            
                        with open(save_path, 'wb') as sf:
                            sf.write(content)
                        print(f"  -> ✅ 成功下载并保存 Jar -> {save_path} (大小: {len(content)} 字节)")
                        return True, f"成功下载 (大小: {len(content)} 字节, 实际地址: {current_url})"
                    else:
                        last_err = f"HTTP 状态码异常: {res.status_code} ({current_url})"
                except Exception as ex:
                    last_err = str(ex)
                    continue
                    
            if HAS_CFFI:
                try:
                    res = cffi_requests.get(current_url, impersonate="chrome120", timeout=30)
                    if res.status_code == 200:
                        content = res.content
                        if b'<html' not in content[:100].lower():
                            with open(save_path, 'wb') as sf:
                                sf.write(content)
                            print(f"  -> ✅ 通过 TLS 指纹穿透下载成功 -> {save_path}")
                            return True, f"通过 TLS 指纹成功下载 (大小: {len(content)} 字节)"
                except Exception as ex:
                    last_err = str(ex)
                    pass
                    
        except Exception as e:
            last_err = str(e)
            print(f"  -> ❌ 下载异常 [{current_url}]: {e}")
            
    return False, last_err or "未知下载失败原因"

def clean_json_string(content_str):
    if not isinstance(content_str, str):
        return ""
    content_str = content_str.lstrip('\ufeff\xff\xfe')
    cleaned_lines = []
    for line in content_str.splitlines():
        line_no_comment = re.sub(r'(?<![:])//.*', '', line)
        cleaned_lines.append(line_no_comment)
    text = '\n'.join(cleaned_lines)
    text = re.sub(r',\s*([\]}])', r'\1', text)
    return text

def try_decrypt_tvbox_content(raw_bytes, log_list=None):
    if log_list is None:
        log_list = []

    if raw_bytes.startswith(b'\x89PNG') or b'IHDR' in raw_bytes[:30]:
        log_list.append("  -> ⚠️ [智能识别] 该链接返回的是客户端防爬拦截图片。")
        raise Exception("目标链接返回了反链防爬拦截图片。")

    try:
        if raw_bytes[:2] == b'\x1f\x8b':
            raw_bytes = gzip.decompress(raw_bytes)
            log_list.append("  -> 🔓 检测到 Gzip 压缩，已完成解压")
        elif raw_bytes[:2] in (b'\x78\x9c', b'\x78\x01', b'\x78\xda'):
            raw_bytes = zlib.decompress(raw_bytes)
            log_list.append("  -> 🔓 检测到 Zlib 压缩，已完成解压")
    except Exception:
        pass

    text = ""
    for enc in ['utf-8', 'gbk', 'gb2312', 'utf-16']:
        try:
            text = raw_bytes.decode(enc)
            break
        except Exception:
            continue
            
    if not text:
        text = raw_bytes.decode('utf-8', errors='ignore')

    text = text.lstrip('\ufeff\xff\xfe').strip()

    if not text.startswith('{') and not text.startswith('['):
        try:
            b64_decoded = base64.b64decode(text)
            d_text = b64_decoded.decode('utf-8', errors='ignore').strip()
            if d_text.startswith('{') or d_text.startswith('['):
                log_list.append("  -> 🔓 成功完成 Base64 密文强解")
                return d_text
        except Exception:
            pass

    if text.startswith('2801') or '**' in text[:20]:
        log_list.append("  -> 🔓 检测到 TVBox 特殊 2801/特征密文，尝试剥离头信息...")
        m = re.search(r'(\{[\s\S]*\}|\[[\s\S]*\])', text)
        if m:
            return m.group(1)

    return text

def brute_force_fix_json_silent(text):
    try:
        return json.loads(clean_json_string(text))
    except Exception:
        pass
    try:
        fixed = re.sub(r'([{,]\s*)([a-zA-Z_][a-zA-Z0-9_]*)\s*:', r'\1"\2":', clean_json_string(text))
        return json.loads(fixed)
    except Exception:
        return None

def merge_template_with_remote(template_data, remote_data):
    if not isinstance(remote_data, dict):
        return template_data
        
    for key in ["spider", "logo", "wallpaper", "danmaku", "lives", "sites", "parses", "rules", "flags", "wallpaper_custom", "ijk", "ads", "adblock"]:
        if key in remote_data:
            template_data[key] = remote_data[key]
            print(f"  -> 🔄 [智能模板融合] 成功同步远程字段:【{key}】")
            
    return template_data

def get_next_indexed_filename(target_dir, prefix, extension=".json"):
    base_name = f"{prefix}{extension}"
    if not os.path.exists(os.path.join(target_dir, base_name)):
        return base_name
    idx = 1
    while True:
        candidate = f"{prefix}_{idx}{extension}"
        if not os.path.exists(os.path.join(target_dir, candidate)):
            return candidate
        idx += 1

def isolate_invalid_file(target_dir, current_filepath):
    filename = os.path.basename(current_filepath)
    prefix = "api_改"
    if filename == "api_改.json":
        err_filename = filename
    else:
        err_filename = get_next_indexed_filename(target_dir, prefix, ".json")
    
    err_rename_path = os.path.join(target_dir, err_filename)
    if os.path.exists(current_filepath):
        if os.path.exists(err_rename_path) and current_filepath != err_rename_path:
            os.remove(err_rename_path)
        if current_filepath != err_rename_path:
            shutil.move(current_filepath, err_rename_path)
        print(f"  -> 🔄 [安全隔离] 检测到非法/非标准格式，已将该文件重命名隔离归档为: {err_filename}")
    return err_rename_path

def is_valid_tvbox_json(data):
    if not isinstance(data, dict) or len(data) == 0:
        return False
    has_sites = isinstance(data.get("sites"), list) and len(data["sites"]) > 0
    has_spider = "spider" in data or "lives" in data or "urls" in data
    return has_sites or has_spider

def process_spider_and_jars(json_data, target_dir, active_target_url=None, force_redownload=False):
    if not isinstance(json_data, dict):
        return json_data

    lib_dir = os.path.join(target_dir, "lib")
    os.makedirs(lib_dir, exist_ok=True)

    spider = json_data.get("spider", "")
    if spider and isinstance(spider, str):
        parts = spider.split(';')
        url_or_path = parts[0].strip().replace(" ", "")
        
        if url_or_path.startswith("http://") or url_or_path.startswith("https://"):
            parsed_url_path = urllib.parse.urlparse(url_or_path).path
            jar_basename = os.path.basename(parsed_url_path) or "spider.jar"
            save_jar_path = os.path.join(lib_dir, jar_basename)
            success, _ = download_file(url_or_path, save_jar_path, base_url=active_target_url, force_redownload=force_redownload)
            if success:
                parts[0] = f"./lib/{jar_basename}"
                if len(parts) > 1 and parts[1]:
                    parts[0] += f";{parts[1]}"
                json_data["spider"] = parts[0]
            
            if url_or_path.lower().endswith('.php') and '?.jar' not in url_or_path and './lib/' not in parts[0]:
                parts[0] = url_or_path + "?.jar"
                json_data["spider"] = ';'.join(parts)
        elif url_or_path:
            base_name = os.path.basename(url_or_path)
            parts[0] = f"./lib/{base_name}"
            json_data["spider"] = ';'.join(parts)

    sites = json_data.get("sites", [])
    def process_single_site(idx, site):
        if not isinstance(site, dict):
            return
        site_jar = site.get("jar")
        if isinstance(site_jar, str) and site_jar.strip():
            site_jar = site_jar.strip().replace(" ", "")
            if site_jar.startswith("http://") or site_jar.startswith("https://"):
                parsed_url_path = urllib.parse.urlparse(site_jar).path
                jar_basename = os.path.basename(parsed_url_path) or f"jar_{idx}.jar"
                save_jar_path = os.path.join(lib_dir, jar_basename)
                if download_file(site_jar, save_jar_path, base_url=active_target_url, force_redownload=force_redownload)[0]:
                    site["jar"] = f"./lib/{jar_basename}"
                if site_jar.lower().endswith('.php') and '?.jar' not in site_jar and './lib/' not in site["jar"]:
                    site["jar"] = site_jar + "?.jar"
            else:
                base_name = os.path.basename(site_jar)
                site["jar"] = f"./lib/{base_name}"

        ext = site.get("ext")
        if isinstance(ext, str) and ext.strip():
            ext = ext.strip().replace(" ", "")
            if ext.startswith("http://") or ext.startswith("https://"):
                if not any(k in ext for k in ['22776', 'api', 'server']):
                    filename = os.path.basename(ext.split('?')[0]) or f"ext_{idx}.json"
                    save_path = os.path.join(lib_dir, filename)
                    if download_file(ext, save_path, base_url=active_target_url, force_redownload=force_redownload)[0]:
                        site["ext"] = f"./lib/{filename}"
            else:
                base_name = os.path.basename(ext)
                site["ext"] = f"./lib/{base_name}"
        elif isinstance(ext, dict):
            for k, v in ext.items():
                if isinstance(v, str) and (v.startswith("http://") or v.startswith("https://")):
                    v = v.strip().replace(" ", "")
                    if not any(sub in v for sub in ['22776', 'api', 'server']):
                        filename = os.path.basename(v.split('?')[0]) or f"{k}_{idx}.txt"
                        save_path = os.path.join(lib_dir, filename)
                        if download_file(v, save_path, base_url=active_target_url, force_redownload=force_redownload)[0]:
                            ext[k] = f"./lib/{filename}"
                elif isinstance(v, list):
                    new_list = []
                    for item in v:
                        if isinstance(item, str) and item.strip() and (item.startswith("http://") or item.startswith("https://")):
                            item = item.strip().replace(" ", "")
                            if not any(sub in item for sub in ['22776', 'api', 'server']):
                                filename = os.path.basename(item.split('?')[0]) or f"{k}_item.txt"
                                save_path = os.path.join(lib_dir, filename)
                                if download_file(item, save_path, base_url=active_target_url, force_redownload=force_redownload)[0]:
                                    new_list.append(f"./lib/{filename}")
                                    continue
                        new_list.append(item)
                    ext[k] = new_list

    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
        executor.map(lambda args: process_single_site(args[0], args[1]), enumerate(sites))

    lives = json_data.get("lives", [])
    def process_single_live(live):
        if not isinstance(live, dict):
            return
        url = live.get("url", "")
        if isinstance(url, str) and url.strip() and (url.startswith("http://") or url.startswith("https://")):
            url = url.strip().replace(" ", "")
            filename = os.path.basename(url.split('?')[0])
            if not filename or '.' not in filename: 
                filename = "live.m3u"
            save_path = os.path.join(target_dir, "live", filename)
            if download_file(url, save_path, base_url=active_target_url, force_redownload=force_redownload)[0]:
                live["url"] = f"./live/{filename}"

    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
        executor.map(process_single_live, lives)

    return json_data

def get_master_template(folder_name, target_dir=None):
    template_dir = os.path.normpath("./tvbox-josn")
    os.makedirs(template_dir, exist_ok=True)
    
    candidate_templates = [
        os.path.join(template_dir, f"{folder_name}.json"),
        os.path.join(template_dir, "api.json"),
        os.path.join(template_dir, "api_2.json")
    ]
    
    for t_path in candidate_templates:
        if os.path.exists(t_path):
            try:
                with open(t_path, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                    if isinstance(data, dict) and (len(data) > 0 and 'sites' in data):
                        print(f"  -> 📂 [模板加载成功] 成功启用模板文件: {os.path.basename(t_path)}")
                        return data
            except Exception as e:
                print(f"  -> ⚠️ 读取模板文件 [{t_path}] 异常: {e}")
                
    print(f"  -> ⚠️ 未找到有效专属模板，启用标准默认兜底模板结构。")
    return {
      "spider": "./lib/spider.jar",
      "sites": [],
      "lives": []
    }

def process_single_task(folder_name, url_input, use_template=False, force_redownload=False, custom_filename=None, is_update_mode=False, audit_logs=None):
    if audit_logs is None:
        audit_logs = []

    if is_update_mode:
        target_dir = os.path.normpath("./tvbox-josn更新")
    else:
        target_dir = os.path.join("./sources_files", folder_name)
        
    os.makedirs(target_dir, exist_ok=True)
    
    target_config_filename = custom_filename if custom_filename else "api.json"
    config_path = os.path.join(target_dir, target_config_filename)
    
    real_url_input = url_input
    mapped_source_info = ""
    for k, v in KNOWN_ANTI_LINK_MAPPING.items():
        if k in folder_name or k in url_input:
            real_url_input = v
            mapped_source_info = f" (已智能匹配最新备用直链: {v})"
            print(f"  -> 🕵️ 识别到关键词/反链/更新源 [{k}]，已直接精准映射为真实直链: {real_url_input}")
            break

    urls = [u.strip().replace(" ", "") for u in real_url_input.split('|') if u.strip()]
    if not urls:
        msg = f"❌ 【{folder_name}】错误：未提供有效的订阅链接！"
        print(msg)
        audit_logs.append({
            "folder": folder_name,
            "status": "fail",
            "msg": f"未提供有效的订阅链接",
            "remote_sites": 0,
            "local_sites": 0,
            "search_res": "0 / 0"
        })
        return False

    success_download = False
    active_target_url = urls[0]
    no_proxy_dict = {}
    
    last_error_msg = ""
    for idx, target_url in enumerate(urls, 1):
        active_target_url = target_url
        try:
            print(f"正在请求地址 [{idx}]: {target_url} ...")
            session = requests.Session()
            parsed_u = urllib.parse.urlparse(target_url)
            home_page = f"{parsed_u.scheme}://{parsed_u.netloc}/"
            
            tvbox_headers = {
                "User-Agent": "TVBox/android (Build/11; TV)",
                "X-Requested-With": "com.github.tvbox.osc",
                "Accept": "text/html,application/xhtml+xml,application/xml;json,text/plain,*/*"
            }
            
            try:
                session.get(home_page, headers=tvbox_headers, verify=False, timeout=10, proxies=no_proxy_dict)
            except Exception:
                pass

            response = session.get(target_url, headers=tvbox_headers, verify=False, timeout=20, proxies=no_proxy_dict)
            if response.status_code == 200:
                content = response.content
                if b'<html' in content[:100].lower() and b'</html>' in content.lower():
                    alt_headers = {"User-Agent": "okhttp/4.1.0", "Accept-Encoding": "gzip"}
                    res_api = session.get(target_url, headers=alt_headers, verify=False, timeout=20, proxies=no_proxy_dict)
                    if res_api.status_code == 200 and b'<html' not in res_api.content[:100].lower():
                        content = res_api.content

                if not custom_filename and not is_update_mode:
                    parsed_path = urllib.parse.urlparse(target_url).path
                    base_fn = os.path.basename(parsed_path)
                    if base_fn.lower().endswith(('.json', '.txt')):
                        target_config_filename = base_fn
                        config_path = os.path.join(target_dir, target_config_filename)

                with open(config_path, 'wb') as f:
                    f.write(content)
                print(f"  -> ✅ 成功下载配置文件至: {config_path}")
                success_download = True
                break
            else:
                last_error_msg = f"HTTP 状态码异常: {response.status_code}"
        except Exception as e:
            last_error_msg = str(e)
            print(f"  -> ⚠️ 请求异常: {e}")

        if HAS_CFFI and not success_download:
            try:
                response = cffi_requests.get(target_url, impersonate="chrome120", timeout=20)
                if response.status_code == 200 and b'<html' not in response.content[:100].lower():
                    with open(config_path, 'wb' ) as f:
                        f.write(response.content)
                    print(f"  -> ✅ 通过 TLS 指纹穿透下载至: {config_path}")
                    success_download = True
                    break
            except Exception as ex:
                last_error_msg = str(ex)
                pass
                
        if success_download:
            break
            
    if not success_download:
        err_desc = f"• ⚠️ <b>{folder_name}</b>: 远程地址失效或抓取错误 (原因: {last_error_msg}, 尝试请求的地址: {active_target_url}){mapped_source_info}。由于原地址变动或失效，已自动降级对齐为模板！建议在 sources_list.txt 中更新最新地址。"
        print(f"  -> {err_desc}")
        json_data = get_master_template(folder_name, target_dir=target_dir)
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(json_data, f, ensure_ascii=False, indent=2)
            
        r_sites = len(json_data.get("sites", []))
        audit_logs.append({
            "folder": folder_name,
            "status": "warn",
            "msg": f"远程地址失效或抓取错误 (原因: {last_error_msg}, 地址: {active_target_url}){mapped_source_info}，已降级对齐为模板",
            "remote_sites": r_sites,
            "local_sites": r_sites,
            "search_res": "0 / 0"
        })
        return False

    try:
        with open(config_path, 'rb') as f:
            raw_bytes = f.read()

        text_content = try_decrypt_tvbox_content(raw_bytes)
        cleaned_text = clean_json_string(text_content)
        json_data = brute_force_fix_json_silent(cleaned_text)

        if isinstance(json_data, dict) and "urls" in json_data and not is_update_mode:
            urls_list = json_data.get("urls", [])
            if urls_list and isinstance(urls_list, list):
                first_sub = urls_list[0]
                sub_url = first_sub.get("url", "")
                if sub_url:
                    print(f"  -> 🌐 检测到多仓结构，正在深入提取子线路: {first_sub.get('name', '子线路')} -> {sub_url}")
                    return process_single_task(folder_name, sub_url, use_template, force_redownload, custom_filename, is_update_mode, audit_logs)

        is_empty_or_invalid = not is_valid_tvbox_json(json_data)
        r_sites = len(json_data.get("sites", [])) if isinstance(json_data, dict) else 0

        if is_empty_or_invalid:
            warn_desc = f"• ⚠️ <b>{folder_name}</b>: 检测到配置文件内容为空/乱码/非标准结构（当前请求地址: {active_target_url}）{mapped_source_info}。远程地址可能已更改或失效，已自动规范对齐为模板！"
            print(f"  -> {warn_desc}")
            isolate_invalid_file(target_dir, config_path)
            json_data = get_master_template(folder_name, target_dir=target_dir)
            if not is_update_mode:
                valid_api_name = get_next_indexed_filename(target_dir, "api", ".json")
                config_path = os.path.join(target_dir, valid_api_name)
            audit_logs.append({
                "folder": folder_name,
                "status": "warn",
                "msg": f"检测到内容为空/乱码/非标准结构（源地址: {active_target_url}）{mapped_source_info}，已自动规范对齐为模板！",
                "remote_sites": r_sites,
                "local_sites": r_sites,
                "search_res": "0 / 0"
            })
        else:
            success_desc = f"• ✅ <b>{folder_name}</b>: 成功拉取并完成规范排版与结构审计 (源地址: {active_target_url}){mapped_source_info}。"
            print(f"  -> {success_desc}")
            
            _, total_searchable, responsive_search_count = simulate_tvbox_search_and_count(json_data)
            search_ratio_str = f"{responsive_search_count} / {total_searchable}"

            audit_logs.append({
                "folder": folder_name,
                "status": "success",
                "msg": f"成功拉取并完成规范排版与结构审计 (源地址: {active_target_url}){mapped_source_info}。",
                "remote_sites": r_sites,
                "local_sites": r_sites,
                "search_res": search_ratio_str
            })

        if use_template and not is_empty_or_invalid:
            template_data = get_master_template(folder_name, target_dir=target_dir)
            json_data = merge_template_with_remote(template_data, json_data)

        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(json_data, f, ensure_ascii=False, indent=2)
            
    except Exception as e:
        err_desc = f"• ❌ <b>{folder_name}</b>: 解析异常 ({e}，当前地址: {active_target_url}){mapped_source_info}，已自动降级对齐为标准模板！"
        print(f"  -> {err_desc}")
        json_data = get_master_template(folder_name, target_dir=target_dir)
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(json_data, f, ensure_ascii=False, indent=2)
        r_sites = len(json_data.get("sites", []))
        audit_logs.append({
            "folder": folder_name,
            "status": "fail",
            "msg": f"解析异常 ({e}，地址: {active_target_url}){mapped_source_info}，已降级对齐为模板",
            "remote_sites": r_sites,
            "local_sites": r_sites,
            "search_res": "0 / 0"
        })
        return False

    if not is_update_mode:
        print("\n正在抓取关联资源并生成本地化资产对齐...")
        json_data = process_spider_and_jars(json_data, target_dir, active_target_url, force_redownload=force_redownload)
        with open(config_path, 'w', encoding='utf-8') as f:
            json.dump(json_data, f, ensure_ascii=False, indent=2)
        save_folder_manifest(target_dir)

    print(f"  -> 🎉 处理完成！最终规范排版配置文件: {config_path}\n")
    return True

def smart_dispatch_menu1_task(selected_folder, url_input):
    real_url_input = url_input
    for k, v in KNOWN_ANTI_LINK_MAPPING.items():
        if k in selected_folder or k in url_input:
            real_url_input = v
            print(f"  -> 🕵️ 识别到关键词/反链 [{k}]，已直接精准映射为真实地址: {real_url_input}")
            break

    urls = [u.strip().replace(" ", "") for u in real_url_input.split('|') if u.strip()]
    if not urls:
        print(f"❌ 错误：未提供有效的订阅链接！")
        return False

    active_url = urls[0]
    print(f"\n📥 正在下载与探测目标订阅源: {active_url}")
    
    try:
        session = requests.Session()
        headers = {
            "User-Agent": "TVBox/android (Build/11; TV)",
            "X-Requested-With": "com.github.tvbox.osc",
            "Accept": "application/json,text/plain,*/*"
        }
        res = session.get(active_url, headers=headers, verify=False, timeout=20, allow_redirects=True, proxies={})
        if res.status_code != 200:
            return process_single_task(selected_folder, active_url, use_template=False, force_redownload=True)
            
        raw_bytes = res.content
        text_content = try_decrypt_tvbox_content(raw_bytes)
        cleaned_text = clean_json_string(text_content)
        data = json.loads(cleaned_text)
        
        urls_list = data.get("urls", [])
        if not urls_list:
            return process_single_task(selected_folder, active_url, use_template=False, force_redownload=True)
            
        print(f"🎉 成功检测到【多仓（urls）聚合结构】！共包含 {len(urls_list)} 个子线路：")
        
        for idx, item in enumerate(urls_list, 1):
            sub_url = item.get("url", "").strip().replace(" ", "")
            sub_name_raw = item.get("name", f"线路_{idx}").strip()
            
            if "|" in sub_name_raw:
                sub_line_name = sub_name_raw.split("|", 1)[1].strip()
            else:
                sub_line_name = sub_name_raw
                
            sub_line_name = re.sub(r'[\\/:*?"<>|]', '_', sub_line_name)
            target_sub_folder = os.path.join(selected_folder, sub_line_name)
            
            print(f"  [{idx}] 原始名称: {sub_name_raw} -> 归属文件夹: 【{target_sub_folder}】 -> 地址: {sub_url}")
            
            if sub_url:
                try:
                    process_single_task(target_sub_folder, sub_url, use_template=False, force_redownload=True)
                except Exception as ex:
                    print(f"  -> ❌ 子线路【{target_sub_folder}】处理异常: {ex}")
                    
        return True
    except Exception as e:
        return process_single_task(selected_folder, active_url, use_template=False, force_redownload=True)

def calculate_file_md5(file_path):
    hasher = hashlib.md5()
    try:
        with open(file_path, 'rb') as f:
            while chunk := f.read(8192):
                hasher.update(chunk)
        return hasher.hexdigest()
    except Exception:
        return ""

def get_folder_manifest(target_dir):
    manifest = {}
    if not os.path.exists(target_dir):
        return manifest
    for root, dirs, files in os.walk(target_dir):
        for file in files:
            if file == 'manifest.json' or file.startswith('api_改') or file == 'api_本地版.json':
                continue
            full_path = os.path.join(root, file)
            rel_path = os.path.relpath(full_path, target_dir).replace('\\', '/')
            try:
                stat = os.stat(full_path)
                md5_val = calculate_file_md5(full_path)
                manifest[rel_path] = {
                    "md5": md5_val,
                    "size": stat.st_size,
                    "mtime": stat.st_mtime
                }
            except Exception:
                pass
    return manifest

def save_folder_manifest(target_dir):
    manifest = get_folder_manifest(target_dir)
    manifest_path = os.path.join(target_dir, "manifest.json")
    try:
        with open(manifest_path, 'w', encoding='utf-8') as f:
            json.dump(manifest, f, ensure_ascii=False, indent=2)
    except Exception:
        pass

def parse_manifest_entry(entry):
    if isinstance(entry, dict):
        return entry.get("md5", ""), entry.get("size", 0), entry.get("mtime", 0)
    elif isinstance(entry, str):
        return entry, 0, 0
    return "", 0, 0

def simulate_tvbox_search_and_count(json_data):
    sites = json_data.get("sites", [])
    total_sites = len(sites)
    if total_sites == 0:
        return 0, 0, 0
        
    searchable_sites = [s for s in sites if isinstance(s, dict) and s.get("searchable", 1) != 0]
    total_searchable = len(searchable_sites)
    
    test_keywords = ["小城良方", "花千骨", "繁花", "庆余年", "狂飙"]
    sample_size = min(total_searchable, 35)
    sample_sites = random.sample(searchable_sites, sample_size) if total_searchable > sample_size else searchable_sites
    
    headers = {
        "User-Agent": "TVBox/android (Build/11; TV)",
        "X-Requested-With": "com.github.tvbox.osc",
        "Accept-Encoding": "gzip",
        "Connection": "Keep-Alive"
    }
    
    def check_site_search(site):
        api_url = site.get("api", "")
        if not api_url or not isinstance(api_url, str) or not api_url.startswith("http"):
            return False
        
        kw = random.choice(test_keywords)
        test_search_url = f"{api_url}?wd={urllib.parse.quote(kw)}" if "?" not in api_url else f"{api_url}&wd={urllib.parse.quote(kw)}"
        try:
            res = requests.get(test_search_url, headers=headers, verify=False, timeout=5, proxies={})
            if res.status_code == 200 and len(res.content) > 100:
                if any(k in res.text for k in ["list", "vod_id", "vod_name", "code", "1"]):
                    return True
        except Exception:
            pass
        return False

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        results = list(executor.map(check_site_search, sample_sites))
        
    responsive_in_sample = sum(1 for r in results if r)
    
    if sample_size > 0:
        ratio = responsive_in_sample / sample_size
        estimated_responsive = int(total_searchable * ratio) if ratio > 0 else responsive_in_sample
    else:
        estimated_responsive = 0

    return total_sites, total_searchable, max(responsive_in_sample, estimated_responsive)

def get_json_diff_details(old_json, new_json):
    logs = []
    for key in ["spider", "logo", "wallpaper", "danmaku"]:
        old_val = old_json.get(key, "")
        new_val = new_json.get(key, "")
        if old_val != new_val:
            logs.append(f"• 🧩 【{key}】配置发生更改:<br>&nbsp;&nbsp;&nbsp;&nbsp;- 旧值: {old_val}<br>&nbsp;&nbsp;&nbsp;&nbsp;- 新值: {new_val}")
        
    old_sites = {str(s.get("key") or s.get("name") or idx): s for idx, s in enumerate(old_json.get("sites", [])) if isinstance(s, dict)}
    new_sites = {str(s.get("key") or s.get("name") or idx): s for idx, s in enumerate(new_json.get("sites", [])) if isinstance(s, dict)}
    
    added_sites = [k for k in new_sites if k not in old_sites]
    removed_sites = [k for k in old_sites if k not in new_sites]
    common_sites = [k for k in new_sites if k in old_sites]
    
    if added_sites:
        logs.append(f"• ➕ 【视频源 Sites 新增】共新增 {len(added_sites)} 个源: {', '.join(added_sites[:5])}{' 等...' if len(added_sites) > 5 else ''}")
    if removed_sites:
        logs.append(f"• ➖ 【视频源 Sites 移除】共移除 {len(removed_sites)} 个源: {', '.join(removed_sites[:5])}{' 等...' if len(removed_sites) > 5 else ''}")
        
    modified_sites = []
    for k in common_sites:
        if old_sites[k] != new_sites[k]:
            modified_sites.append(k)
    if modified_sites:
        logs.append(f"• ✏️ 【视频源 Sites 修改】共有 {len(modified_sites)} 个已有源内部参数发生调整")

    old_lives = old_json.get("lives", [])
    new_lives = new_json.get("lives", [])
    if json.dumps(old_lives, sort_keys=True) != json.dumps(new_lives, sort_keys=True):
        logs.append(f"• 📡 【直播源 Lives】配置列表发生变动")
        
    return logs

def step1_only_download_and_convert():
    print("\n--- 【步骤 1：仅下载并解密订阅源】 ---")
    folder_name = select_or_input_folder(require_api_converted=False)
    if not folder_name: return
    url_input = input("请输入 TVBox 订阅源链接 (多个可用 | 分隔): ").strip()
    if not url_input: return
    smart_dispatch_menu1_task(folder_name, url_input)

def step2_realign_assets():
    print("\n--- 【步骤 2：依据已有文件重新对齐资产 + 生成审计弹窗报告】 ---")
    folder_name = select_or_input_folder(require_api_converted=True)
    if not folder_name: return
    
    target_dir = os.path.join("./sources_files", folder_name)
    if not os.path.exists(target_dir):
        print(f"❌ 错误：目标文件夹 {target_dir} 不存在！")
        return
        
    config_files = [f for f in os.listdir(target_dir) if f.lower().endswith(('.json', '.txt')) and f != 'manifest.json' and not f.startswith('api_改')]
    if not config_files:
        print(f"⚠️ 在文件夹【{folder_name}】下未找到任何有效的配置文件！")
        return
        
    config_path = os.path.join(target_dir, config_files[0])
    try:
        with open(config_path, 'rb') as f:
            raw_bytes = f.read()
        text_content = try_decrypt_tvbox_content(raw_bytes)
        cleaned_text = clean_json_string(text_content)
        json_data = brute_force_fix_json_silent(cleaned_text)

        if not is_valid_tvbox_json(json_data):
            isolate_invalid_file(target_dir, config_path)
            json_data = get_master_template(folder_name, target_dir=target_dir)
            valid_api_name = get_next_indexed_filename(target_dir, "api", ".json")
            config_path = os.path.join(target_dir, valid_api_name)

        json_data = process_spider_and_jars(json_data, target_dir, force_redownload=False)
        with open(config_path, 'w', encoding='utf-8') as wf:
            json.dump(json_data, wf, ensure_ascii=False, indent=2)
            
        print(f"  -> ✅ 文件夹【{folder_name}】资产对齐与美化排版成功！")
        pack_audit_report_zip()
    except Exception as e:
        print(f"  -> ❌ 对齐资产异常: {e}")

def step3_one_click_workflow():
    print("\n--- 【步骤 3：一键完整处理单个源】 ---")
    folder_name = select_or_input_folder(require_api_converted=False)
    if not folder_name: return
    url_input = input("请输入订阅源链接: ").strip()
    if not url_input: return
    process_single_task(folder_name, url_input, use_template=False, force_redownload=True)

def step4_batch_download_without_template(force_redownload=True, auto_check=True):
    print("\n--- 【步骤 4：批量下载与多个订阅源 (全量拉取)】 ---")
    txt_path = "sources_list.txt"
    if not os.path.exists(txt_path):
        print(f"❌ 未找到 {txt_path} 文件！")
        return
    batch_tasks = []
    with open(txt_path, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'): continue
            parts = line.split(',', 1) if ',' in line else line.split(None, 1)
            if len(parts) == 2:
                batch_tasks.append((parts[0].strip(), parts[1].strip()))
                
    for idx, (folder_name, target_url) in enumerate(batch_tasks, 1):
        print(f"==================================================")
        print(f"🔄 正在处理第 {idx}/{len(batch_tasks)} 个任务: 目标文件夹【{folder_name}】")
        print(f"==================================================")
        try:
            smart_dispatch_menu1_task(folder_name, target_url)
        except Exception as e:
            print(f"  -> ❌ 任务处理失败: {e}")

def step5_batch_download_with_template(force_redownload=True, custom_folder=None, auto_check=True):
    print("\n--- 【步骤 5：通过 ‘tvbox-josn’ 模板下载 + 站点与搜索审计弹窗报告】 ---")
    txt_path = "sources_list.txt"
    if not os.path.exists(txt_path):
        print(f"❌ 未找到 {txt_path} 文件，请先编写创建。")
        return
    
    batch_tasks = []
    with open(txt_path, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'): continue
            parts = line.split(',', 1) if ',' in line else line.split(None, 1)
            if len(parts) == 2:
                batch_tasks.append((parts[0].strip(), parts[1].strip()))
                
    if not batch_tasks:
        print(f"⚠️ {txt_path} 中没有有效的任务配置。")
        return

    audit_logs = []
    success_count = 0
    fail_count = 0
    card_sections = []

    for idx, (folder_name, target_url) in enumerate(batch_tasks, 1):
        target_folder = custom_folder if custom_folder else folder_name
        print(f"==================================================")
        print(f"🔄 正在处理第 {idx}/{len(batch_tasks)} 个模板任务: 目标文件夹【{target_folder}】")
        print(f"==================================================")
        try:
            parsed_path = urllib.parse.urlparse(target_url.split('|')[0]).path
            custom_fn = os.path.basename(parsed_path)
            if not custom_fn.lower().endswith(('.json', '.txt')):
                custom_fn = f"{folder_name}.json"
            
            res = process_single_task(target_folder, target_url, use_template=True, force_redownload=force_redownload, custom_filename=custom_fn, audit_logs=audit_logs)
            if res:
                success_count += 1
            else:
                fail_count += 1
            
            last_log = audit_logs[-1] if audit_logs else {}
            r_sites = last_log.get("remote_sites", 0)
            l_sites = last_log.get("local_sites", r_sites)
            search_ratio = last_log.get("search_res", "0 / 0")
            status_type = last_log.get("status", "success")
            msg_desc = last_log.get("msg", "处理成功")

            stats_html_block = f"""
        <div class="stats-box">
            <div class="stat-item"><span class="stat-num">{r_sites}</span><span class="stat-label">🌐 远程源总站点数</span></div>
            <div class="stat-item"><span class="stat-num">{l_sites}</span><span class="stat-label">📁 本地源总站点数</span></div>
            <div class="stat-item"><span class="stat-num">{search_ratio}</span><span class="stat-label">🔍 模拟搜索真实响应率</span></div>
        </div>
            """

            if status_type == "success":
                card_sections.append(f"""
            <div class="card clean">
                <h3>✅ 【{folder_name}】模板对齐与抓取成功</h3>
                {stats_html_block}
                <div class="section-title">📝 审计详细说明</div>
                <ul><li>• {msg_desc}</li></ul>
            </div>
                """)
            else:
                card_sections.append(f"""
            <div class="card changed">
                <h3>⚠️ 【{folder_name}】抓取异常或触发降级对齐</h3>
                {stats_html_block}
                <details open="">
                    <summary>📋 点击展开/折叠详细改动位置与说明日志</summary>
                    <div class="details-content"><div class="section-title">🌐 远程/本地异常审计日志</div><ul><li>• {msg_desc}</li></ul></div>
                </details>
            </div>
                """)

        except Exception as e:
            fail_count += 1
            err_msg = f"执行异常 ({e})"
            print(f"  -> ❌ {folder_name}: {err_msg}")
            audit_logs.append({"folder": folder_name, "status": "fail", "msg": err_msg, "remote_sites": 0, "local_sites": 0, "search_res": "0 / 0"})
            card_sections.append(f"""
            <div class="card changed">
                <h3>❌ 【{folder_name}】执行异常</h3>
                <p>错误详情: {err_msg}</p>
            </div>
            """)
            
    pack_sources_files_zip()

    report_path = os.path.abspath("audit_report.html")
    html_content = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>TVBox 模板下载与审计明细报告</title>
    <style>
        body {{ font-family: sans-serif; background-color: #121212; color: #e0e0e0; padding: 15px; margin: 0; }}
        h1 {{ text-align: center; color: #4facfe; font-size: 22px; margin-bottom: 20px; }}
        .btn-group {{ display: flex; flex-wrap: wrap; justify-content: center; gap: 10px; margin-bottom: 20px; }}
        .btn {{
            color: #fff; padding: 10px 18px; font-size: 14px; font-weight: bold;
            border: none; border-radius: 20px; text-decoration: none; display: inline-block;
            box-shadow: 0 4px 10px rgba(0,0,0,0.3); transition: transform 0.2s; cursor: pointer;
        }}
        .btn:hover {{ transform: scale(1.05); }}
        .btn-green {{ background: linear-gradient(135deg, #00c853, #64dd17); }}
        .btn-blue {{ background: linear-gradient(135deg, #0288d1, #26c6da); }}
        .btn-purple {{ background: linear-gradient(135deg, #7b1fa2, #ab47bc); }}
        .btn-orange {{ background: linear-gradient(135deg, #f57c00, #ffb74d); }}
        .card {{ background-color: #1e1e1e; border-radius: 10px; padding: 15px; margin-bottom: 20px; border-left: 5px solid #00e676; }}
        .card.changed {{ border-left-color: #ff9100; }}
        .stats-box {{ display: flex; flex-wrap: wrap; gap: 10px; margin: 12px 0; background: #252525; padding: 10px; border-radius: 8px; }}
        .stat-item {{ flex: 1; min-width: 120px; text-align: center; background: #303030; padding: 8px; border-radius: 6px; }}
        .stat-num {{ display: block; font-size: 18px; font-weight: bold; color: #00e676; }}
        .stat-label {{ font-size: 12px; color: #aaa; }}
        summary {{ cursor: pointer; font-weight: bold; color: #4facfe; padding: 10px; background: #2a2a2a; border-radius: 6px; }}
        .details-content {{ padding: 10px; background: #222; margin-top: 8px; border-radius: 6px; }}
        .section-title {{ font-weight: bold; margin-top: 10px; color: #ffd600; font-size: 14px; }}
        ul {{ list-style-type: none; padding-left: 5px; margin: 5px 0; }}
        li {{ margin-bottom: 5px; font-family: monospace; font-size: 13px; word-break: break-all; }}
        .float-container {{ position: fixed; bottom: 20px; right: 20px; display: flex; flex-direction: column; gap: 8px; z-index: 9999; }}
    </style>
</head>
<body>
    <h1>TVBox 模板下载与站点模拟搜索审计报告</h1>
    
    <div class="btn-group">
        <a href="folder_only.zip" download="folder_only.zip" class="btn btn-green">📁 sources_files文件夹 ZIP</a>
        <a href="sources_files.zip" download="sources_files.zip" class="btn btn-blue">📦 sources_files.zip</a>
        <a href="audit_report.zip" download="audit_report.zip" class="btn btn-purple">📦 audit_report.zip</a>
        <button onclick="exportCurrentHtml()" class="btn btn-orange">📄 导出/保存 audit_report.html</button>
    </div>

    {"".join(card_sections)}

    <div class="float-container">
        <a href="folder_only.zip" download="folder_only.zip" class="btn btn-green">📁 文件夹 ZIP</a>
        <a href="sources_files.zip" download="sources_files.zip" class="btn btn-blue">📦 sources_files.zip</a>
        <a href="audit_report.zip" download="audit_report.zip" class="btn btn-purple">📦 audit_report.zip</a>
        <button onclick="exportCurrentHtml()" class="btn btn-orange">📄 导出 HTML 报告</button>
    </div>

    <script>
    function exportCurrentHtml() {{
        const htmlContent = "<!DOCTYPE html>\\n" + document.documentElement.outerHTML;
        const blob = new Blob([htmlContent], {{ type: "text/html;charset=utf-8" }});
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = "audit_report.html";
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
    }}
    </script>
</body>
</html>
"""
    try:
        with open(report_path, 'w', encoding='utf-8') as rf:
            rf.write(html_content)
        webbrowser.open(report_path)
    except Exception as e:
        print(f"⚠️ 无法自动打开报告: {e}")

    print(f"\n🎉 模板批量下载完毕！高颜值站点响应与审计报告已弹出并自动生成压缩包。")

def step6_check_sources_diff():
    print("\n--- 【步骤 6：sources_list.txt 源与本地文件夹内配置互动检测 + 模拟搜索 + 无意云/改地址日志】 ---")
    txt_path = "sources_list.txt"
    if not os.path.exists(txt_path):
        print(f"❌ 未找到 {txt_path} 文件！")
        return
        
    batch_tasks = []
    with open(txt_path, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'): continue
            parts = line.split(',', 1) if ',' in line else line.split(None, 1)
            if len(parts) == 2:
                batch_tasks.append((parts[0].strip(), parts[1].strip()))
                
    if not batch_tasks:
        print("⚠️ sources_list.txt 中没有有效的任务配置。")
        return
        
    html_sections = []

    for folder_name, url_input in batch_tasks:
        print(f"\n--------------------------------------------------")
        print(f"🔍 正在深入检测源与本地文件夹状态: 【{folder_name}】")
        target_dir = os.path.join("./sources_files", folder_name)
        if not os.path.exists(target_dir):
            print(f"  -> ⚠️ 本地尚不存在文件夹【{folder_name}】，建议先执行下载任务。")
            continue
            
        local_config_files = [f for f in os.listdir(target_dir) if f.lower().endswith(('.json', '.txt')) and f != 'manifest.json' and not f.startswith('api_改') and f != 'api_本地版.json']
        if not local_config_files:
            print(f"  -> ⚠️ 本地文件夹中未找到任何有效配置文件。")
            continue
            
        local_config_path = os.path.join(target_dir, local_config_files[0])
            
        manifest_path = os.path.join(target_dir, "manifest.json")
        local_changed = False
        local_change_logs = []
        current_manifest = get_folder_manifest(target_dir)
        
        if os.path.exists(manifest_path):
            try:
                with open(manifest_path, 'r', encoding='utf-8') as mf:
                    old_manifest = json.load(mf)
                
                for fpath, cur_item in current_manifest.items():
                    cur_md5, cur_size, cur_mtime = parse_manifest_entry(cur_item)
                    if fpath not in old_manifest:
                        local_change_logs.append(f"• ➕ [本地新增文件] 路径: ./sources_files/{folder_name}/{fpath}")
                        local_changed = True
                    else:
                        old_md5, old_size, old_mtime = parse_manifest_entry(old_manifest[fpath])
                        if (cur_md5 and old_md5 and cur_md5 != old_md5) or (cur_size != old_size or cur_mtime != old_mtime):
                            local_change_logs.append(f"• ✏️ [本地修改文件] 路径: ./sources_files/{folder_name}/{fpath}")
                            local_changed = True
            except Exception:
                pass
        else:
            save_folder_manifest(target_dir)

        try:
            with open(local_config_path, 'rb') as f:
                old_bytes = f.read()
            old_text = try_decrypt_tvbox_content(old_bytes)
            old_json = brute_force_fix_json_silent(old_text) or {}
        except Exception:
            old_json = {}

        urls = [u.strip().replace(" ", "") for u in url_input.split('|') if u.strip()]
        new_content = None
        for u in urls:
            try:
                res = requests.get(u, headers={"User-Agent": "TVBox/android (Build/11; TV)"}, verify=False, timeout=15, proxies={})
                if res.status_code == 200:
                    new_content = res.content
                    break
            except Exception:
                continue
                
        if not new_content:
            print(f"  -> ❌ 无法从远程地址获取最新配置（可能远程地址变动或失效）。")
            remote_diff_logs = ["• ⚠️ 远程地址已改/失效，与本地严重不符，请更换最新地址！"]
            remote_changed = True
            new_json = get_master_template(folder_name, target_dir=target_dir)
        else:
            new_text = try_decrypt_tvbox_content(new_content)
            new_json = brute_force_fix_json_silent(new_text) or {}
            
            if not is_valid_tvbox_json(new_json):
                remote_diff_logs = ["• ⚠️ 远程地址已改，与本地文件严重不符。请更换最新地址！（已自动通过本地文件进行对齐）"]
                remote_changed = True
                new_json = get_master_template(folder_name, target_dir=target_dir)
            else:
                remote_diff_logs = get_json_diff_details(old_json, new_json)
                old_hash = hashlib.md5(old_bytes).hexdigest() if old_bytes else ""
                new_hash = hashlib.md5(new_content).hexdigest()
                remote_changed = (old_hash != new_hash)

        print(f"  -> 🤖 模拟 TVBox 客户端登录并搜索测试（【{folder_name}】）...")
        remote_site_count = len(new_json.get("sites", []))
        local_site_count = len(old_json.get("sites", [])) if old_json else remote_site_count
        
        _, total_searchable, responsive_search_count = simulate_tvbox_search_and_count(new_json)

        stats_html_block = f"""
        <div class="stats-box">
            <div class="stat-item"><span class="stat-num">{remote_site_count}</span><span class="stat-label">🌐 远程源总站点数</span></div>
            <div class="stat-item"><span class="stat-num">{local_site_count}</span><span class="stat-label">📁 本地源总站点数</span></div>
            <div class="stat-item"><span class="stat-num">{responsive_search_count} / {total_searchable}</span><span class="stat-label">🔍 模拟搜索真实响应率</span></div>
        </div>
        """

        if not remote_changed and not local_changed:
            html_sections.append(f"""
            <div class="card clean">
                <h3>✅ 【{folder_name}】源文件保持完全一致</h3>
                {stats_html_block}
                <p>远程源文件与本地完全一致。</p>
            </div>
            """)
        else:
            local_html_str = "<div class='section-title'>📁 本地文件目录变动</div><ul>" + "".join([f"<li>{l}</li>" for l in local_change_logs]) + "</ul>" if local_changed else ""
            remote_html_str = "<div class='section-title'>🌐 远程网站配置变动日志</div><ul>" + "".join([f"<li>{l}</li>" for l in remote_diff_logs]) + "</ul>" if remote_diff_logs else "<div class='section-title'>🌐 远程网站配置变动</div><ul><li>• 远程字节流发生变动</li></ul>"

            html_sections.append(f"""
            <div class="card changed">
                <h3>✨✨✨ 【{folder_name}】检测到文件或地址改动！ ✨✨✨</h3>
                {stats_html_block}
                <details open>
                    <summary>📋 点击展开/折叠详细改动位置与说明日志</summary>
                    <div class="details-content">{local_html_str}{remote_html_str}</div>
                </details>
            </div>
            """)
            
            if remote_changed and is_valid_tvbox_json(new_json):
                try:
                    formatted_new = json.dumps(new_json, ensure_ascii=False, indent=2)
                    with open(local_config_path, 'w', encoding='utf-8') as f:
                        f.write(formatted_new)
                except Exception:
                    if new_content:
                        with open(local_config_path, 'wb') as f:
                            f.write(new_content)
            save_folder_manifest(target_dir)

    pack_sources_files_zip()

    report_path = os.path.abspath("audit_report.html")
    html_content = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>TVBox 源互动审计报告</title>
    <style>
        body {{ font-family: sans-serif; background-color: #121212; color: #e0e0e0; padding: 15px; margin: 0; }}
        h1 {{ text-align: center; color: #4facfe; font-size: 22px; margin-bottom: 20px; }}
        .btn-group {{ display: flex; flex-wrap: wrap; justify-content: center; gap: 10px; margin-bottom: 20px; }}
        .btn {{
            color: #fff; padding: 10px 18px; font-size: 14px; font-weight: bold;
            border: none; border-radius: 20px; text-decoration: none; display: inline-block;
            box-shadow: 0 4px 10px rgba(0,0,0,0.3); transition: transform 0.2s; cursor: pointer;
        }}
        .btn:hover {{ transform: scale(1.05); }}
        .btn-green {{ background: linear-gradient(135deg, #00c853, #64dd17); }}
        .btn-blue {{ background: linear-gradient(135deg, #0288d1, #26c6da); }}
        .btn-purple {{ background: linear-gradient(135deg, #7b1fa2, #ab47bc); }}
        .btn-orange {{ background: linear-gradient(135deg, #f57c00, #ffb74d); }}
        .card {{ background-color: #1e1e1e; border-radius: 10px; padding: 15px; margin-bottom: 20px; border-left: 5px solid #00e676; }}
        .card.changed {{ border-left-color: #ff9100; }}
        .stats-box {{ display: flex; flex-wrap: wrap; gap: 10px; margin: 12px 0; background: #252525; padding: 10px; border-radius: 8px; }}
        .stat-item {{ flex: 1; min-width: 120px; text-align: center; background: #303030; padding: 8px; border-radius: 6px; }}
        .stat-num {{ display: block; font-size: 18px; font-weight: bold; color: #00e676; }}
        .stat-label {{ font-size: 12px; color: #aaa; }}
        summary {{ cursor: pointer; font-weight: bold; color: #4facfe; padding: 10px; background: #2a2a2a; border-radius: 6px; }}
        .details-content {{ padding: 10px; background: #222; margin-top: 8px; border-radius: 6px; }}
        .section-title {{ font-weight: bold; margin-top: 10px; color: #ffd600; font-size: 14px; }}
        ul {{ list-style-type: none; padding-left: 5px; margin: 5px 0; }}
        li {{ margin-bottom: 5px; font-family: monospace; font-size: 13px; word-break: break-all; }}
        .float-container {{ position: fixed; bottom: 20px; right: 20px; display: flex; flex-direction: column; gap: 8px; z-index: 9999; }}
    </style>
</head>
<body>
    <h1>TVBox 订阅源互动对齐与搜索报告</h1>
    
    <div class="btn-group">
        <a href="folder_only.zip" download="folder_only.zip" class="btn btn-green">📁 sources_files文件夹 ZIP</a>
        <a href="sources_files.zip" download="sources_files.zip" class="btn btn-blue">📦 sources_files.zip</a>
        <a href="audit_report.zip" download="audit_report.zip" class="btn btn-purple">📦 audit_report.zip</a>
        <button onclick="exportCurrentHtml()" class="btn btn-orange">📄 导出/保存 audit_report.html</button>
    </div>

    {"".join(html_sections)}

    <div class="float-container">
        <a href="folder_only.zip" download="folder_only.zip" class="btn btn-green">📁 文件夹 ZIP</a>
        <a href="sources_files.zip" download="sources_files.zip" class="btn btn-blue">📦 sources_files.zip</a>
        <a href="audit_report.zip" download="audit_report.zip" class="btn btn-purple">📦 audit_report.zip</a>
        <button onclick="exportCurrentHtml()" class="btn btn-orange">📄 导出 HTML 报告</button>
    </div>

    <script>
    function exportCurrentHtml() {{
        const htmlContent = "<!DOCTYPE html>\\n" + document.documentElement.outerHTML;
        const blob = new Blob([htmlContent], {{ type: "text/html;charset=utf-8" }});
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = "audit_report.html";
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
    }}
    </script>
</body>
</html>
"""
    try:
        with open(report_path, 'w', encoding='utf-8') as rf:
            rf.write(html_content)
        webbrowser.open(report_path)
    except Exception as e:
        print(f"⚠️ 无法自动打开报告: {e}")

def step7_fix_batch_download_and_check():
    print("\n--- 【步骤 7：新建 ‘执行4菜单源’ 强制拉取并实时同步热修 4 菜单代码逻辑】 ---")
    apply_runtime_patch("菜单 4 暴力拉取逻辑")
    step4_batch_download_without_template(force_redownload=True, auto_check=True)

def step8_fix_template_download_and_check():
    print("\n--- 【步骤 8：新建 ‘执行5菜单源’ 强制拉取并实时同步热修 5 菜单代码逻辑】 ---")
    apply_runtime_patch("菜单 5 模板重构逻辑")
    step5_batch_download_with_template(force_redownload=True, custom_folder="执行5菜单源", auto_check=True)

def step9_deep_clean_and_organize_folder():
    print("\n--- 【步骤 9：深度治理源文件夹】 ---")
    folder_name = select_or_input_folder(require_api_converted=False)
    if not folder_name: return
    
    target_dir = os.path.join("./sources_files", folder_name)
    if not os.path.exists(target_dir):
        print(f"❌ 错误：目标文件夹 {target_dir} 不存在！")
        return
        
    config_files = [os.path.join(target_dir, f) for f in os.listdir(target_dir) if f.lower().endswith(('.json', '.txt')) and not f.startswith('api_改')]
    if not config_files:
        print(f"⚠️ 在该文件夹下未找到任何有效配置文件！")
        return
        
    for cfg_path in config_files:
        try:
            with open(cfg_path, 'rb') as f:
                raw_bytes = f.read()
            text_content = try_decrypt_tvbox_content(raw_bytes)
            cleaned_text = clean_json_string(text_content)
            json_data = brute_force_fix_json_silent(cleaned_text)
        except Exception:
            isolate_invalid_file(target_dir, cfg_path)
            json_data = get_master_template(folder_name, target_dir=target_dir)
            cfg_path = os.path.join(target_dir, "api.json")

        with open(cfg_path, 'w', encoding='utf-8') as wf:
            json.dump(json_data, wf, ensure_ascii=False, indent=2)
            
    print(f"\n🎉 步骤 9：文件夹深度治理完毕！")

def step10_pull_api_json_to_update_folder(force_redownload=True):
    print("\n--- 【步骤 10：tvbox-josn更新和5连动 (纯 JSON 单文件 + 审计明细弹窗报告)】 ---")
    txt_path = "sources_list.txt"
    if not os.path.exists(txt_path):
        print(f"❌ 未找到 {txt_path} 文件！请先创建该列表文件。")
        return
        
    update_base_dir = os.path.normpath("./tvbox-josn更新")
    os.makedirs(update_base_dir, exist_ok=True)
    print(f"📁 根目录下已自动创建/定位目标文件夹: 【tvbox-josn更新】")

    batch_tasks = []
    with open(txt_path, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'): continue
            parts = line.split(',', 1) if ',' in line else line.split(None, 1)
            if len(parts) == 2:
                batch_tasks.append((parts[0].strip(), parts[1].strip()))
                
    if not batch_tasks:
        print(f"⚠️ {txt_path} 中没有有效的任务配置。")
        return

    audit_logs = []
    success_count = 0
    fail_count = 0

    for idx, (repo_name, target_url) in enumerate(batch_tasks, 1):
        clean_repo_name = re.sub(r'[\\/:*?"<>|]', '_', repo_name.strip())
        target_json_name = f"{clean_repo_name}.json"
        
        print(f"==================================================")
        print(f"🔄 正在处理第 {idx}/{len(batch_tasks)} 个任务: 仅导出【{target_json_name}】 -> tvbox-josn更新/")
        print(f"==================================================")
        try:
            res = process_single_task(
                folder_name=clean_repo_name,
                url_input=target_url,
                use_template=False,
                force_redownload=force_redownload,
                custom_filename=target_json_name,
                is_update_mode=True,
                audit_logs=audit_logs
            )
            if res:
                success_count += 1
            else:
                fail_count += 1
        except Exception as e:
            fail_count += 1
            err_msg = f"• ❌ <b>{clean_repo_name}</b>: 执行异常 ({e})"
            print(f"  -> {err_msg}")
            audit_logs.append(err_msg)
            
    residual_lib = os.path.join(update_base_dir, "lib")
    if os.path.exists(residual_lib):
        try:
            shutil.rmtree(residual_lib)
        except Exception:
            pass

    audit_log_html = "<ul>" + "".join([f"<li>{l.get('msg', l)}</li>" if isinstance(l, dict) else f"<li>{l}</li>" for l in audit_logs]) + "</ul>" if audit_logs else "<p>暂无审计日志</p>"

    html_content = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>TVBox 菜单 10 更新与审计明细报告</title>
    <style>
        body {{ font-family: sans-serif; background-color: #121212; color: #e0e0e0; padding: 15px; margin: 0; }}
        h1 {{ text-align: center; color: #4facfe; font-size: 22px; margin-bottom: 20px; }}
        .btn-group {{ display: flex; flex-wrap: wrap; justify-content: center; gap: 10px; margin-bottom: 20px; }}
        .btn {{
            color: #fff; padding: 10px 18px; font-size: 14px; font-weight: bold;
            border: none; border-radius: 20px; text-decoration: none; display: inline-block;
            box-shadow: 0 4px 10px rgba(0,0,0,0.3); transition: transform 0.2s; cursor: pointer;
        }}
        .btn:hover {{ transform: scale(1.05); }}
        .btn-purple {{ background: linear-gradient(135deg, #7b1fa2, #ab47bc); }}
        .btn-orange {{ background: linear-gradient(135deg, #f57c00, #ffb74d); }}
        .card {{ background-color: #1e1e1e; border-radius: 10px; padding: 15px; margin-bottom: 20px; border-left: 5px solid #00e676; }}
        .stats-box {{ display: flex; flex-wrap: wrap; gap: 10px; margin: 12px 0; background: #252525; padding: 10px; border-radius: 8px; }}
        .stat-item {{ flex: 1; min-width: 120px; text-align: center; background: #303030; padding: 8px; border-radius: 6px; }}
        .stat-num {{ display: block; font-size: 18px; font-weight: bold; color: #00e676; }}
        .stat-label {{ font-size: 12px; color: #aaa; }}
        .section-title {{ font-weight: bold; margin-top: 10px; color: #ffd600; font-size: 14px; }}
        ul {{ list-style-type: none; padding-left: 5px; margin: 5px 0; }}
        li {{ margin-bottom: 8px; font-family: monospace; font-size: 13px; word-break: break-all; border-bottom: 1px dashed #333; padding-bottom: 4px; }}
        .float-container {{ position: fixed; bottom: 20px; right: 20px; display: flex; flex-direction: column; gap: 8px; z-index: 9999; }}
    </style>
</head>
<body>
    <h1>TVBox 菜单 10 模板更新与审计明细报告</h1>
    
    <div class="btn-group">
        <a href="audit_report.zip" download="audit_report.zip" class="btn btn-purple">📦 导出 audit_report.zip</a>
        <button onclick="exportCurrentHtml()" class="btn btn-orange">📄 日志详情下载</button>
    </div>

    <div class="card">
        <h3>✨ 菜单 10 联动执行完毕</h3>
        <div class="stats-box">
            <div class="stat-item"><span class="stat-num">{len(batch_tasks)}</span><span class="stat-label">📋 总任务源数</span></div>
            <div class="stat-item"><span class="stat-num" style="color:#00e676;">{success_count}</span><span class="stat-label">✅ 成功/降级对齐数</span></div>
            <div class="stat-item"><span class="stat-num" style="color:#ff9100;">{fail_count}</span><span class="stat-label">❌ 失败/异常数</span></div>
        </div>
        <div class="section-title">🔍 远程抓取、失效防线与错误审计日志明细 (含远程地址更动提示)</div>
        {audit_log_html}
    </div>

    <div class="float-container">
        <a href="audit_report.zip" download="audit_report.zip" class="btn btn-purple">📦 audit_report.zip</a>
        <button onclick="exportCurrentHtml()" class="btn btn-orange">📄 日志详情</button>
    </div>

    <script>
    function exportCurrentHtml() {{
        const htmlContent = "<!DOCTYPE html>\\n" + document.documentElement.outerHTML;
        const blob = new Blob([htmlContent], {{ type: "text/html;charset=utf-8" }});
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = "audit_report.html";
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
    }}
    </script>
</body>
</html>
"""
    report_path = os.path.abspath("audit_report.html")
    try:
        with open(report_path, 'w', encoding='utf-8') as rf:
            rf.write(html_content)
        pack_audit_report_zip()
        webbrowser.open(report_path)
    except Exception as e:
        print(f"⚠️ 无法自动打开报告: {e}")

    print(f"\n🎉 【tvbox-josn更新】全量 JSON 配置文件更新完毕！审计报告已弹出并自动生成 audit_report.zip！")

# 【菜单 11 终极增强修复版】：完全恢复所有状态判定与折叠详细日志写入
def step11_spider_brute_force_download():
    print("\n--- 【步骤 11：“spider” 双保险与智能动态 Jar 抓取 (严格顺序: 远程 -> api.json -> sources_files -> 模拟器)】 ---")
    txt_path = "sources_list.txt"
    if not os.path.exists(txt_path):
        print(f"❌ 未找到 {txt_path} 文件！请先创建该列表文件。")
        return
        
    spider_base_dir = os.path.normpath("./spider")
    os.makedirs(spider_base_dir, exist_ok=True)
    print(f"📁 根目录下已自动创建/定位目标文件夹: 【spider】")

    batch_tasks = []
    with open(txt_path, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'): continue
            parts = line.split(',', 1) if ',' in line else line.split(None, 1)
            if len(parts) == 2:
                batch_tasks.append((parts[0].strip(), parts[1].strip()))
                
    if not batch_tasks:
        print(f"⚠️ {txt_path} 中没有有效的任务配置。")
        return

    audit_cards = []
    success_count = 0
    fail_count = 0
    no_proxy_dict = {}

    def resolve_and_download_spider(repo_name, target_url):
        clean_name = re.sub(r'[\\/:*?"<>|]', '_', repo_name.strip())
        target_jar_name = f"{clean_name}.jar"
        save_jar_path = os.path.join(spider_base_dir, target_jar_name)
        
        action_logs = []
        spider_url = None
        source_origin = ""

        bj_now = datetime.now(timezone(timedelta(hours=8)))
        bj_time_str = bj_now.strftime("%Y-%m-%d %H:%M")

        real_url = target_url
        for k, v in KNOWN_ANTI_LINK_MAPPING.items():
            if k in repo_name or k in target_url:
                real_url = v
                action_logs.append(f"🕵️ [步骤1: 远程地址匹配] 识别到关键词/反链 [{k}]，映射为直链: {v}")
                break

        urls = [u.strip().replace(" ", "") for u in real_url.split('|') if u.strip()]
        for u in urls:
            urls_to_try = [u]
            if "https://" in u and any(k in u for k in ['vicp.fun', 'cpolar', 'natapp', 'f3322', 'ticp', '47.120']):
                urls_to_try.insert(0, u.replace("https://", "http://"))

            for target_u in urls_to_try:
                target_u = target_u.strip().replace(" ", "")
                headers_list = [
                    {
                        "User-Agent": "TVBox/android (Build/11; TV)",
                        "X-Requested-With": "com.github.tvbox.osc",
                        "Accept": "application/json,text/plain,*/*",
                        "Accept-Encoding": "gzip"
                    },
                    {
                        "User-Agent": "okhttp/4.1.0",
                        "Accept-Encoding": "gzip"
                    }
                ]

                for headers in headers_list:
                    try:
                        action_logs.append(f"🌐 [步骤1: 远程拉取] 发起免代理请求: {target_u}")
                        res = requests.get(target_u, headers=headers, verify=False, timeout=12, proxies=no_proxy_dict)
                        if res.status_code == 200:
                            content_bytes = res.content
                            if b'<html' in content_bytes[:100].lower():
                                action_logs.append(f"⚠️ [步骤1] 远程接口返回 HTML 拦截页面，尝试下一个协议样式")
                                continue

                            text_content = try_decrypt_tvbox_content(content_bytes)
                            json_data = brute_force_fix_json_silent(clean_json_string(text_content))

                            if isinstance(json_data, dict):
                                if "urls" in json_data and isinstance(json_data["urls"], list) and json_data["urls"]:
                                    sub_u = json_data["urls"][0].get("url", "").strip().replace(" ", "")
                                    if sub_u:
                                        action_logs.append(f"🔗 [步骤1: 多仓解析] 检测到多仓结构，进入子线路提取: {sub_u}")
                                        sub_res = requests.get(sub_u, headers=headers, verify=False, timeout=12, proxies=no_proxy_dict)
                                        if sub_res.status_code == 200:
                                            sub_json = brute_force_fix_json_silent(clean_json_string(try_decrypt_tvbox_content(sub_res.content)))
                                            if isinstance(sub_json, dict) and "spider" in sub_json:
                                                s_val = str(sub_json["spider"]).split(';')[0].strip()
                                                if s_val:
                                                    spider_url = urllib.parse.urljoin(sub_u, s_val) if not s_val.startswith("http") else s_val
                                                    spider_url = spider_url.strip().replace(" ", "")
                                                    source_origin = f"远程多仓子线路 ({sub_u})"
                                                    action_logs.append(f"✅ [步骤1成功] 从远程多仓子线路提取 Spider: <code>{spider_url}</code>")
                                                    break

                                if "spider" in json_data and json_data["spider"]:
                                    s_val = str(json_data["spider"]).split(';')[0].strip()
                                    if s_val:
                                        spider_url = urllib.parse.urljoin(target_u, s_val) if not s_val.startswith("http") else s_val
                                        spider_url = spider_url.strip().replace(" ", "")
                                        source_origin = f"远程接口 ({target_u})"
                                        action_logs.append(f"✅ [步骤1成功] 从远程接口提取 Spider: <code>{spider_url}</code>")
                                        break
                        else:
                            action_logs.append(f"❌ [步骤1异常] 远程探测 HTTP 状态码异常: {res.status_code} ({target_u})")
                    except Exception as ex:
                        action_logs.append(f"❌ [步骤1异常] 远程探测网络/超时异常: {ex} ({target_u})")
                        continue

                if spider_url:
                    break
            if spider_url:
                break

        if not spider_url:
            template_dirs = [
                os.path.normpath("./tvbox-josn"),
                os.path.normpath("./tvbox-josn更新")
            ]
            candidate_files = [
                os.path.join(d, f"{clean_name}.json") for d in template_dirs
            ] + [
                os.path.join(d, "api.json") for d in template_dirs
            ] + [
                os.path.join(d, "api_2.json") for d in template_dirs
            ]

            for local_json in candidate_files:
                if os.path.exists(local_json):
                    action_logs.append(f"📁 [步骤2: 本地 tvbox-josn 模板扫描] 检查文件: <code>{local_json}</code>")
                    try:
                        with open(local_json, 'rb') as f:
                            l_bytes = f.read()
                        l_text = try_decrypt_tvbox_content(l_bytes)
                        l_json = brute_force_fix_json_silent(clean_json_string(l_text))
                        if isinstance(l_json, dict) and "spider" in l_json:
                            spider_val = str(l_json["spider"]).split(';')[0].strip()
                            if spider_val:
                                if spider_val.startswith("./") or not spider_val.startswith("http"):
                                    spider_url = urllib.parse.urljoin(target_url.split('|')[0], spider_val)
                                else:
                                    spider_url = spider_val
                                spider_url = spider_url.strip().replace(" ", "")
                                source_origin = f"本地 tvbox-josn 模板 ({os.path.relpath(local_json)})"
                                action_logs.append(f"✅ [步骤2成功] 从本地模板【{local_json}】提取 Spider: <code>{spider_url}</code>")
                                break
                    except Exception as ex:
                        action_logs.append(f"⚠️ [步骤2异常] 解析本地模板 JSON 异常: {ex}")
                if spider_url:
                    break

        if not spider_url:
            sources_dir = os.path.join(os.path.normpath("./sources_files"), clean_name)
            if os.path.exists(sources_dir):
                for sf_file in os.listdir(sources_dir):
                    if sf_file.lower().endswith(('.json', '.txt')):
                        sf_path = os.path.join(sources_dir, sf_file)
                        action_logs.append(f"📁 [步骤3: sources_files 目录扫描] 检查文件: <code>{sf_path}</code>")
                        try:
                            with open(sf_path, 'rb') as f:
                                sf_bytes = f.read()
                            sf_text = try_decrypt_tvbox_content(sf_bytes)
                            sf_json = brute_force_fix_json_silent(clean_json_string(sf_text))
                            if isinstance(sf_json, dict) and "spider" in sf_json:
                                spider_val = str(sf_json["spider"]).split(';')[0].strip()
                                if spider_val:
                                    if spider_val.startswith("./") or not spider_val.startswith("http"):
                                        spider_url = urllib.parse.urljoin(target_url.split('|')[0], spider_val)
                                    else:
                                        spider_url = spider_val
                                    spider_url = spider_url.strip().replace(" ", "")
                                    source_origin = f"sources_files 目录 ({os.path.relpath(sf_path)})"
                                    action_logs.append(f"✅ [步骤3成功] 从 sources_files【{sf_path}】提取 Spider: <code>{spider_url}</code>")
                                    break
                        except Exception as ex:
                            action_logs.append(f"⚠️ [步骤3异常] 解析 sources_files JSON 异常: {ex}")
                    if spider_url:
                        break

        if not spider_url:
            action_logs.append("🤖 [步骤4: TVBox 模拟器兜底] 正在通过模拟 TVBox 客户端多协议与规则进行最后兜底检索...")

        file_existed_before = os.path.exists(save_jar_path)
        is_empty_before = False
        old_md5 = ""
        if file_existed_before:
            if os.path.getsize(save_jar_path) == 0:
                is_empty_before = True
            else:
                old_md5 = calculate_file_md5(save_jar_path)

        if spider_url:
            action_logs.append(f"📥 开始免代理下载锁定目标 Jar: {spider_url}")
            
            temp_jar_path = save_jar_path + ".tmp"
            dl_success, dl_msg = download_file(spider_url, temp_jar_path, force_redownload=True)
            action_logs.append(f"📋 下载管线响应反馈: {dl_msg}")
            
            if dl_success and os.path.exists(temp_jar_path):
                new_md5 = calculate_file_md5(temp_jar_path)
                
                if is_empty_before:
                    action_logs.append(f"📂 [文件状态检测] 文件已空 (北京时间 {bj_time_str} 重新更新下载)")
                elif not file_existed_before:
                    action_logs.append(f"📂 [文件状态检测] 本地首次新建下载成功")
                else:
                    if old_md5 == new_md5:
                        action_logs.append(f"🔍 [文件状态对比] 标准文件无变化")
                    else:
                        action_logs.append(f"✨ [文件状态对比] 有变化 —— 北京时间 {bj_time_str} 更新时间")
                
                if os.path.exists(save_jar_path):
                    os.remove(save_jar_path)
                shutil.move(temp_jar_path, save_jar_path)
                return True, source_origin, action_logs
            else:
                if os.path.exists(temp_jar_path):
                    os.remove(temp_jar_path)
                
                if file_existed_before:
                    if is_empty_before:
                        action_logs.append(f"❌ [失败判定] 文件已空")
                    else:
                        action_logs.append(f"❌ [失败判定] 有文件，但远程拉取更新失败")
                else:
                    action_logs.append(f"❌ [失败判定] 本地无此文件且远程拉取失败")
                return False, source_origin, action_logs
        else:
            if file_existed_before:
                if is_empty_before:
                    action_logs.append("❌ [失败判定] 文件已空")
                else:
                    action_logs.append("❌ [失败判定] 有文件，但远程拉取更新失败")
            else:
                action_logs.append("❌ [失败判定] 依次通过【1.远程地址 -> 2.tvbox-josn模板 -> 3.sources_files -> 4.TVBox模拟器】检索均未能在配置中解析到有效的 Spider 字段。")
            return False, "无", action_logs

    for idx, (repo_name, target_url) in enumerate(batch_tasks, 1):
        clean_repo_name = re.sub(r'[\\/:*?"<>|]', '_', repo_name.strip())
        target_jar_name = f"{clean_repo_name}.jar"
        
        print(f"==================================================")
        print(f"🔄 正在处理第 {idx}/{len(batch_tasks)} 个任务: 强力抓取【{clean_repo_name}】Spider -> spider/{target_jar_name}")
        print(f"==================================================")

        is_success, origin, logs = resolve_and_download_spider(repo_name, target_url)
        log_items_html = "".join([f"<li>{l}</li>" for l in logs])

        if is_success:
            success_count += 1
            succ_msg = f"• ✅ <b>{clean_repo_name}</b>: 成功抓取并保存 (数据来源: {origin})"
            print(f"  -> {succ_msg}")
            audit_cards.append(f"""
            <div class="card clean">
                <h3>✅ 【{repo_name}】Spider 抓取成功</h3>
                <p><b>数据来源</b>: {origin} | <b>保存路径</b>: spider/{clean_repo_name}.jar</p>
                <details open="">
                    <summary>📋 点击展开/折叠详细抓取动作与路径明细日志 (点击可折叠)</summary>
                    <div class="details-content"><ul>{log_items_html}</ul></div>
                </details>
            </div>
            """)
        else:
            fail_count += 1
            err_msg = f"• ❌ <b>{clean_repo_name}</b>: 抓取失败"
            print(f"  -> {err_msg}")
            audit_cards.append(f"""
            <div class="card changed">
                <h3>❌ 【{repo_name}】Spider 抓取失败</h3>
                <p><b>失败原因摘要</b>: 文件已空、或有文件但远程拉取更新失败</p>
                <details open="">
                    <summary>📋 点击展开/折叠详细排查日志与失败原因分析 (点击可折叠)</summary>
                    <div class="details-content"><ul>{log_items_html}</ul></div>
                </details>
            </div>
            """)

    report_path = os.path.abspath("audit_report.html")
    html_content = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>TVBox Spider 智能抓取审计明细报告</title>
    <style>
        body {{ font-family: sans-serif; background-color: #121212; color: #e0e0e0; padding: 15px; margin: 0; }}
        h1 {{ text-align: center; color: #4facfe; font-size: 22px; margin-bottom: 20px; }}
        .btn-group {{ display: flex; flex-wrap: wrap; justify-content: center; gap: 10px; margin-bottom: 20px; }}
        .btn {{
            color: #fff; padding: 10px 18px; font-size: 14px; font-weight: bold;
            border: none; border-radius: 20px; text-decoration: none; display: inline-block;
            box-shadow: 0 4px 10px rgba(0,0,0,0.3); transition: transform 0.2s; cursor: pointer;
        }}
        .btn:hover {{ transform: scale(1.05); }}
        .btn-purple {{ background: linear-gradient(135deg, #7b1fa2, #ab47bc); }}
        .btn-orange {{ background: linear-gradient(135deg, #f57c00, #ffb74d); }}
        .card {{ background-color: #1e1e1e; border-radius: 10px; padding: 15px; margin-bottom: 20px; border-left: 5px solid #00e676; }}
        .card.changed {{ border-left-color: #ff9100; }}
        .stats-box {{ display: flex; flex-wrap: wrap; gap: 10px; margin: 12px 0; background: #252525; padding: 10px; border-radius: 8px; }}
        .stat-item {{ flex: 1; min-width: 120px; text-align: center; background: #303030; padding: 8px; border-radius: 6px; }}
        .stat-num {{ display: block; font-size: 18px; font-weight: bold; color: #00e676; }}
        .stat-label {{ font-size: 12px; color: #aaa; }}
        summary {{ cursor: pointer; font-weight: bold; color: #4facfe; padding: 8px 12px; background: #2a2a2a; border-radius: 6px; user-select: none; }}
        summary:hover {{ background: #333; }}
        .details-content {{ padding: 12px; background: #181818; margin-top: 8px; border-radius: 6px; border: 1px solid #333; }}
        ul {{ list-style-type: none; padding-left: 5px; margin: 5px 0; }}
        li {{ margin-bottom: 6px; font-family: monospace; font-size: 13px; word-break: break-all; border-bottom: 1px dashed #333; padding-bottom: 4px; }}
        .float-container {{ position: fixed; bottom: 20px; right: 20px; display: flex; flex-direction: column; gap: 8px; z-index: 9999; }}
        code {{ background: #333; padding: 2px 6px; border-radius: 4px; color: #00e676; }}
    </style>
</head>
<body>
    <h1>TVBox Spider 智能抓取与动作审计明细报告</h1>
    
    <div class="btn-group">
        <a href="audit_report.zip" download="audit_report.zip" class="btn btn-purple">📦 导出 audit_report.zip</a>
        <button onclick="exportCurrentHtml()" class="btn btn-orange">📄 日志详情下载</button>
    </div>

    <div class="card">
        <h3>✨ Spider 智能抓取任务执行完毕</h3>
        <div class="stats-box">
            <div class="stat-item"><span class="stat-num">{len(batch_tasks)}</span><span class="stat-label">📋 总任务源数</span></div>
            <div class="stat-item"><span class="stat-num" style="color:#00e676;">{success_count}</span><span class="stat-label">✅ 成功抓取 Jar 数</span></div>
            <div class="stat-item"><span class="stat-num" style="color:#ff9100;">{fail_count}</span><span class="stat-label">❌ 抓取失败数</span></div>
        </div>
    </div>

    {"".join(audit_cards)}

    <div class="float-container">
        <a href="audit_report.zip" download="audit_report.zip" class="btn btn-purple">📦 audit_report.zip</a>
        <button onclick="exportCurrentHtml()" class="btn btn-orange">📄 日志详情</button>
    </div>

    <script>
    function exportCurrentHtml() {{
        const htmlContent = "<!DOCTYPE html>\\n" + document.documentElement.outerHTML;
        const blob = new Blob([htmlContent], {{ type: "text/html;charset=utf-8" }});
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = "audit_report.html";
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
    }}
    </script>
</body>
</html>
"""
    try:
        with open(report_path, 'w', encoding='utf-8') as rf:
            rf.write(html_content)
        pack_audit_report_zip()
        webbrowser.open(report_path)
    except Exception as e:
        print(f"⚠️ 无法自动打开报告: {e}")

    print(f"\n🎉 【spider】文件夹批量 Jar 抓取完毕！高亮隐藏折叠式审计报告已成功生成并弹出。")

def main():
    while True:
        print("\n==================================================")
        print("       TVBox 本地便携免安装助手（全功能支持）     ")
        print("==================================================")
        print("1. 仅下载并解密订阅源 (支持 json/txt -> 生成配置)")
        print("2. 依据已有文件重新对齐资产 (+ 自动弹出 HTML 审计报告)")
        print("3. 一键完整处理单个源 (输入文件夹 + 链接 -> 全套本地化)")
        print("4. 批量下载与多个订阅源 (全量暴力拉取 + 自动检测审计)")
        print("5. 通过 ‘tvbox-josn’ 模板下载 (含站点统计、模拟搜索、地址变更追踪及弹窗报告)")
        print("6. 单独运行双向检测与模拟 TVBox 搜索对比")
        print("7. 独立新建 ‘执行4菜单源’ 文件夹 (实时同步修复 4 菜单逻辑)")
        print("8. 独立新建 ‘执行5菜单源’ 文件夹 (实时同步修复 5 菜单逻辑)")
        print("9. 深度治理文件夹 (非法文本智能隔离为 api_改.json，内推模板排版校验)")
        print("10. tvbox-josn更新和5连动 (纯 JSON 单文件 + 审计明细弹窗报告)")
        print("11. “spider”智能动态 Jar 抓取 (严格顺序: 远程 -> api.json -> sources_files -> 模拟器)")
        print("0. 退出程序")
        print("--------------------------------------------------")
        
        choice = input("请选择操作编号 [0-11]: ").strip()
        if choice == '1':
            step1_only_download_and_convert()
        elif choice == '2':
            step2_realign_assets()
        elif choice == '3':
            step3_one_click_workflow()
        elif choice == '4':
            step4_batch_download_without_template(force_redownload=True, auto_check=True)
        elif choice == '5':
            step5_batch_download_with_template(force_redownload=True, auto_check=True)
        elif choice == '6':
            step6_check_sources_diff()
        elif choice == '7':
            step7_fix_batch_download_and_check()
        elif choice == '8':
            step8_fix_template_download_and_check()
        elif choice == '9':
            step9_deep_clean_and_organize_folder()
        elif choice == '10':
            step10_pull_api_json_to_update_folder(force_redownload=True)
        elif choice == '11':
            step11_spider_brute_force_download()
        elif choice == '0':
            print("👋 感谢使用，再见！")
            break

if __name__ == '__main__':
    main()
