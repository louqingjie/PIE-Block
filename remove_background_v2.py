from PIL import Image
from collections import deque

# 打开图片
image_path = r"c:\Users\louqi\Desktop\pie-block\assets\images\image-1784962225614.png"
img = Image.open(image_path).convert("RGBA")
width, height = img.size
pixels = img.load()

# 参数：容差值（判断相似颜色）
tolerance = 50

# 从四个角作为种子，取平均颜色作为背景色参考
corners = [
    pixels[0, 0],
    pixels[width - 1, 0],
    pixels[0, height - 1],
    pixels[width - 1, height - 1],
]
bg_r = sum(c[0] for c in corners) // 4
bg_g = sum(c[1] for c in corners) // 4
bg_b = sum(c[2] for c in corners) // 4
print(f"背景参考色: ({bg_r}, {bg_g}, {bg_b})")

def is_bg(px):
    return (
        abs(px[0] - bg_r) <= tolerance
        and abs(px[1] - bg_g) <= tolerance
        and abs(px[2] - bg_b) <= tolerance
    )

# 从边缘所有像素做 BFS 泛洪
visited = [[False] * height for _ in range(width)]
queue = deque()

for x in range(width):
    for y in (0, height - 1):
        if is_bg(pixels[x, y]) and not visited[x][y]:
            visited[x][y] = True
            queue.append((x, y))
for y in range(height):
    for x in (0, width - 1):
        if is_bg(pixels[x, y]) and not visited[x][y]:
            visited[x][y] = True
            queue.append((x, y))

# 4邻域泛洪
while queue:
    x, y = queue.popleft()
    pixels[x, y] = (pixels[x, y][0], pixels[x, y][1], pixels[x, y][2], 0)
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        nx, ny = x + dx, y + dy
        if 0 <= nx < width and 0 <= ny < height and not visited[nx][ny]:
            if is_bg(pixels[nx, ny]):
                visited[nx][ny] = True
                queue.append((nx, ny))

output_path = r"c:\Users\louqi\Desktop\pie-block\assets\images\image-1784962225614_transparent.png"
img.save(output_path, "PNG")
print(f"图片已保存到: {output_path}")
