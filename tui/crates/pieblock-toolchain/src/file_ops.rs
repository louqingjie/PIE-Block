//! 文件操作的有限重试（Windows 杀毒/索引器短暂占用句柄时）。

use std::io;
use std::path::Path;
use std::time::Duration;

/// 对文件系统操作做有限退避重试；非 IO 错误直接返回。
pub fn retry_file_system<T>(
    mut action: impl FnMut() -> io::Result<T>,
    attempts: u32,
    initial_delay: Duration,
    max_delay: Duration,
    sleep: &dyn Fn(Duration),
) -> io::Result<T> {
    let mut delay = initial_delay;
    for attempt in 1..=attempts.max(1) {
        match action() {
            Ok(value) => return Ok(value),
            Err(error) if attempt < attempts => {
                if !delay.is_zero() {
                    sleep(delay);
                }
                let next = delay.as_millis().saturating_mul(2);
                delay = Duration::from_millis(
                    u64::try_from(next.min(max_delay.as_millis())).unwrap_or(0),
                );
                let _ = error;
            }
            Err(error) => return Err(error),
        }
    }
    unreachable!("attempts >= 1")
}

/// 递归复制目录（逐文件重试瞬时占用）。
pub fn copy_directory(
    source: &Path,
    destination: &Path,
    sleep: &dyn Fn(Duration),
) -> io::Result<()> {
    let default_retry = |action: &mut dyn FnMut() -> io::Result<()>| {
        retry_file_system(
            action,
            4,
            Duration::from_millis(120),
            Duration::from_secs(2),
            sleep,
        )
    };
    default_retry(&mut || std::fs::create_dir_all(destination))?;
    for entry in std::fs::read_dir(source)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        let target = destination.join(entry.file_name());
        if file_type.is_dir() {
            copy_directory(&entry.path(), &target, sleep)?;
        } else if file_type.is_file() {
            default_retry(&mut || std::fs::copy(entry.path(), &target).map(|_| ()))?;
        }
    }
    Ok(())
}
