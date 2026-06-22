# Milvus Ingress

Манифесты и инструкция перенесены в папку **[ingress/](ingress/README.md)**.

```bash
cd ingress
# заменить плейсхолдеры в *.yaml
kubectl apply -f milvus-ui-ingress.yaml
kubectl apply -f milvus-rest-ingress.yaml
kubectl apply -f milvus-grpc-ingress.yaml
```
