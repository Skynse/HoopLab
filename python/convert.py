from ultralytics import YOLO
model = YOLO('best.pt')
model.export(format='tflite',imgsz=640,opset=11)
