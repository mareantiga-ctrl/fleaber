select li.id, li.ref_code, batata_live_item_stock(li.id) as stock
from live_items li
where li.live_id='c3af87a7-a962-4af5-bb35-90b39a03ede9';
