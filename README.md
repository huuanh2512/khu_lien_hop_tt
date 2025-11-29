# Khu Liên Hợp Thể Thao — UI reset

Giao diện Flutter đã được xóa và khởi tạo lại tối giản theo yêu cầu. Chỉ giữ lại phần liên quan tới cơ sở dữ liệu/backend trong thư mục `server/` (MongoDB + API) và các model/service cần thiết phía client để dùng lại sau này.

## Trạng thái hiện tại

- Ứng dụng Flutter chỉ hiển thị một màn hình tối giản để bắt đầu thiết kế lại.
- Toàn bộ màn hình UI cũ (screens, widgets, utils liên quan UI) đã được xóa.
- Thư mục `server/` và dữ liệu vẫn giữ nguyên, không bị ảnh hưởng.

## Chạy thử

1. Cài dependency:
	- Mở workspace này trong VS Code.
	- Chạy lệnh lấy package (Flutter) và đảm bảo backend vẫn hoạt động nếu bạn cần tích hợp sau.

2. Chạy ứng dụng Flutter: chọn device và chạy project như bình thường.

## Bước tiếp theo gợi ý

- Thiết kế lại luồng màn hình từ trang chủ tối giản hiện tại.
- Kết nối lại tới API trong `server/` thông qua `lib/services/*` khi cần.
- Viết test mới tương ứng với UI mới.
