# PyMilvus для Milvus 2.5.x (инструкция на русском)

Для вашего текущего Milvus (`milvusdb/milvus:v2.5.0`) используйте:

- **Рекомендуемая версия:** `pymilvus==2.5.16`
- **Практика:** держать SDK в той же ветке, что и сервер (`Milvus 2.5.x` + `PyMilvus 2.5.x`)

## Установка

```bash
pip install "pymilvus==2.5.16"
```

Вариант для air-gap:

```bash
# На стенде с интернетом
pip download "pymilvus==2.5.16" -d wheels/

# В изолированном контуре
pip install --no-index --find-links wheels/ "pymilvus==2.5.16"
```

## Пример 1: Подключение и проверка версии сервера

```python
from pymilvus import MilvusClient

client = MilvusClient(uri="http://localhost:19530", token="root:Milvus")
print("server version:", client.get_server_version())
client.close()
```

## Пример 2: Создание коллекции и вставка данных

```python
from pymilvus import MilvusClient, DataType

client = MilvusClient(uri="http://localhost:19530", token="root:Milvus")

collection_name = "demo_products"
dim = 8

if client.has_collection(collection_name=collection_name):
    client.drop_collection(collection_name=collection_name)

schema = client.create_schema()
schema.add_field("id", DataType.INT64, is_primary=True, auto_id=False)
schema.add_field("vector", DataType.FLOAT_VECTOR, dim=dim)
schema.add_field("name", DataType.VARCHAR, max_length=128)
schema.add_field("price", DataType.FLOAT)
schema.add_field("in_stock", DataType.BOOL)

index_params = client.prepare_index_params()
index_params.add_index(
    field_name="vector",
    index_type="HNSW",
    metric_type="COSINE",
    params={"M": 16, "efConstruction": 200},
)

client.create_collection(
    collection_name=collection_name,
    schema=schema,
    index_params=index_params,
)

rows = [
    {"id": 1, "vector": [0.1, 0.2, 0.3, 0.4, 0.1, 0.0, 0.2, 0.9], "name": "item-a", "price": 10.5, "in_stock": True},
    {"id": 2, "vector": [0.9, 0.1, 0.0, 0.3, 0.4, 0.1, 0.2, 0.1], "name": "item-b", "price": 19.9, "in_stock": True},
    {"id": 3, "vector": [0.0, 0.2, 0.8, 0.3, 0.2, 0.7, 0.4, 0.1], "name": "item-c", "price": 99.0, "in_stock": False},
]

res = client.insert(collection_name=collection_name, data=rows)
print("inserted:", res)
```

## Пример 3: Векторный поиск с фильтром

```python
query_vec = [0.1, 0.2, 0.3, 0.4, 0.1, 0.0, 0.2, 0.9]

results = client.search(
    collection_name="demo_products",
    data=[query_vec],
    filter="price >= 10 and in_stock == true",
    limit=3,
    output_fields=["id", "name", "price", "in_stock"],
    search_params={"metric_type": "COSINE", "params": {"ef": 64}},
)

for hits in results:
    for hit in hits:
        print(hit["id"], hit["distance"], hit["entity"]["name"], hit["entity"]["price"])
```

## Пример 4: Query по scalar-фильтру и get по ID

```python
filtered = client.query(
    collection_name="demo_products",
    filter="price > 15",
    output_fields=["id", "name", "price"],
    limit=100,
)
print("query rows:", filtered)

by_ids = client.get(
    collection_name="demo_products",
    ids=[1, 3],
    output_fields=["id", "name", "price", "in_stock"],
)
print("get rows:", by_ids)
```

## Пример 5: Upsert и delete

```python
upsert_payload = [
    {"id": 2, "vector": [0.95, 0.1, 0.0, 0.3, 0.4, 0.1, 0.2, 0.1], "name": "item-b-updated", "price": 21.0, "in_stock": True},
    {"id": 4, "vector": [0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2, 0.2], "name": "item-d-new", "price": 7.5, "in_stock": True},
]
print(client.upsert(collection_name="demo_products", data=upsert_payload))

print(client.delete(collection_name="demo_products", ids=[3]))
# или:
# print(client.delete(collection_name="demo_products", filter="price < 8"))
```

## Практические замечания

- Фиксируйте одну версию SDK на окружение: `2.5.16`.
- В deployment-манифестах фиксируйте и образ Milvus, и версию PyMilvus.
- Для auth используйте `token="user:password"` и храните учетные данные в секретах.
