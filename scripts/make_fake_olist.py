"""Generate small Olist-shaped CSVs so the SQL pipeline can be smoke-tested
without downloading the real 120MB dataset. NOT part of the deliverable —
this exists only to prove the scripts run end to end."""
import csv, os, random, datetime as dt

random.seed(7)
OUT = "data/raw"
os.makedirs(OUT, exist_ok=True)

N_PEOPLE, N_SELLERS, N_PRODUCTS = 800, 60, 300
CATS = ["cama_mesa_banho", "beleza_saude", "esporte_lazer", "informatica_acessorios",
        "moveis_decoracao", "utilidades_domesticas", "relogios_presentes"]
CATS_EN = ["bed_bath_table", "health_beauty", "sports_leisure", "computers_accessories",
           "furniture_decor", "housewares", "watches_gifts"]
STATES = ["SP", "RJ", "MG", "RS", "PR", "BA"]


def w(name, header, rows):
    with open(f"{OUT}/{name}", "w", newline="", encoding="utf-8") as f:
        wr = csv.writer(f)
        wr.writerow(header)
        wr.writerows(rows)


def hid(p, i):
    return f"{p}{i:032x}"


# geolocation: several points per zip prefix, plus a few bad geocodes
geo = []
for z in range(1000, 1120):
    for _ in range(random.randint(1, 4)):
        geo.append([z, round(random.uniform(-30, -5), 6), round(random.uniform(-60, -40), 6),
                    f"city{z%17}", random.choice(STATES)])
geo.append([1001, 45.0, 10.0, "bad_geocode", "SP"])
w("olist_geolocation_dataset.csv",
  ["geolocation_zip_code_prefix", "geolocation_lat", "geolocation_lng",
   "geolocation_city", "geolocation_state"], geo)

# people -> customer_unique_id; each order gets a fresh customer_id
people = [hid("u", i) for i in range(N_PEOPLE)]
cust_rows, cust_ids = [], []
cid = 0
orders, items, pays, revs = [], [], [], []
base = dt.datetime(2017, 1, 5)

for pi, uid in enumerate(people):
    n_orders = random.choices([1, 2, 3], weights=[80, 15, 5])[0]
    zipp = random.randint(1000, 1119)
    st = random.choice(STATES)
    t = base + dt.timedelta(days=random.randint(0, 500))
    for k in range(n_orders):
        c = hid("c", cid); cid += 1
        cust_rows.append([c, uid, zipp, f"city{zipp%17}", st])
        oid = hid("o", len(orders))
        purch = t + dt.timedelta(days=k * random.randint(20, 200))
        promised = purch + dt.timedelta(days=random.randint(8, 30))
        late_bias = random.random()
        actual = promised + dt.timedelta(days=random.randint(-20, 4) if late_bias > .18
                                         else random.randint(2, 25))
        status = "delivered" if random.random() > .04 else random.choice(
            ["canceled", "shipped", "processing"])
        deliv = actual.strftime("%Y-%m-%d %H:%M:%S") if status == "delivered" else ""
        orders.append([oid, c, status, purch.strftime("%Y-%m-%d %H:%M:%S"),
                       (purch + dt.timedelta(hours=6)).strftime("%Y-%m-%d %H:%M:%S"),
                       (purch + dt.timedelta(days=2)).strftime("%Y-%m-%d %H:%M:%S") if status != "processing" else "",
                       deliv, promised.strftime("%Y-%m-%d %H:%M:%S")])
        total = 0.0
        for li in range(1, random.choices([1, 2, 3], weights=[75, 18, 7])[0] + 1):
            price = round(random.uniform(15, 400), 2)
            fr = round(random.uniform(7, 45), 2)
            total += price + fr
            items.append([oid, li, hid("p", random.randrange(N_PRODUCTS)),
                          hid("s", random.randrange(N_SELLERS)),
                          (purch + dt.timedelta(days=3)).strftime("%Y-%m-%d %H:%M:%S"),
                          price, fr])
        pays.append([oid, 1, random.choice(["credit_card", "boleto", "voucher", "debit_card"]),
                     random.choice([1, 1, 2, 3, 6, 10]), round(total, 2)])
        if status == "delivered":
            lateness = (actual - promised).days
            score = 5 if lateness < -5 else 4 if lateness <= 0 else 3 if lateness <= 7 else random.choice([1, 1, 2])
            revs.append([hid("r", len(revs)), oid, score,
                         (actual + dt.timedelta(days=1)).strftime("%Y-%m-%d %H:%M:%S"),
                         (actual + dt.timedelta(days=3)).strftime("%Y-%m-%d %H:%M:%S")])

w("olist_customers_dataset.csv",
  ["customer_id", "customer_unique_id", "customer_zip_code_prefix",
   "customer_city", "customer_state"], cust_rows)
w("olist_orders_dataset.csv",
  ["order_id", "customer_id", "order_status", "order_purchase_timestamp",
   "order_approved_at", "order_delivered_carrier_date",
   "order_delivered_customer_date", "order_estimated_delivery_date"], orders)
w("olist_order_items_dataset.csv",
  ["order_id", "order_item_id", "product_id", "seller_id",
   "shipping_limit_date", "price", "freight_value"], items)
w("olist_order_payments_dataset.csv",
  ["order_id", "payment_sequential", "payment_type",
   "payment_installments", "payment_value"], pays)
w("olist_order_reviews_dataset.csv",
  ["review_id", "order_id", "review_score", "review_comment_title",
   "review_comment_message", "review_creation_date", "review_answer_timestamp"],
  [[r[0], r[1], r[2], "", "muito bom\nrecomendo", r[3], r[4]] for r in revs])

prods = []
for i in range(N_PRODUCTS):
    ci = random.randrange(len(CATS))
    cat = CATS[ci] if random.random() > .05 else ""   # some products have no category
    prods.append([hid("p", i), cat, 50, 400, random.randint(1, 5),
                  random.randint(100, 9000), random.randint(10, 60),
                  random.randint(5, 40), random.randint(8, 50)])
w("olist_products_dataset.csv",
  ["product_id", "product_category_name", "product_name_lenght",
   "product_description_lenght", "product_photos_qty", "product_weight_g",
   "product_length_cm", "product_height_cm", "product_width_cm"], prods)

w("olist_sellers_dataset.csv",
  ["seller_id", "seller_zip_code_prefix", "seller_city", "seller_state"],
  [[hid("s", i), random.randint(1000, 1119), f"city{i%17}", random.choice(STATES)]
   for i in range(N_SELLERS)])

w("product_category_name_translation.csv",
  ["product_category_name", "product_category_name_english"],
  list(zip(CATS, CATS_EN)))

print(f"people={len(people)} customers={len(cust_rows)} orders={len(orders)} "
      f"items={len(items)} reviews={len(revs)}")
