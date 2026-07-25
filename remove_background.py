from PIL import Image

# 打开图片
image_path = r"c:\Users\louqi\Desktop\pie-block\assets\images\image-1784962225614.png"
img = Image.open(image_path)

# 转换为RGBA模式（支持透明）
img = img.convert("RGBA")

# 获取像素数据
data = img.getdata()

new_data = []
for item in data:
    # 将白色/浅灰色背景设置为透明
    # 判断RGB值都大于200（接近白色）
    if item[0] > 200 and item[1] > 200 and item[2] > 200:
        # 设置为透明
        new_data.append((item[0], item[1], item[2], 0))
    else:
        # 保持原样
        new_data.append(item)

# 更新图片数据
img.putdata(new_data)

# 保存图片
output_path = r"c:\Users\louqi\Desktop\pie-block\assets\images\image-1784962225614_transparent.png"
img.save(output_path, "PNG")

print(f"图片已保存到: {output_path}")
