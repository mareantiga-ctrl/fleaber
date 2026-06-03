-- Quantidade por artigo + quantidade por encomenda.
-- Não remove nem altera funcionalidades existentes.

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS quantity integer NOT NULL DEFAULT 1;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'products_quantity_check'
  ) THEN
    ALTER TABLE public.products
      ADD CONSTRAINT products_quantity_check CHECK (quantity >= 1);
  END IF;
END
$$;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS quantity integer NOT NULL DEFAULT 1;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'orders_quantity_check'
  ) THEN
    ALTER TABLE public.orders
      ADD CONSTRAINT orders_quantity_check CHECK (quantity >= 1);
  END IF;
END
$$;

COMMENT ON COLUMN public.products.quantity IS
  'Quantidade disponível para compra deste artigo (mínimo 1).';

COMMENT ON COLUMN public.orders.quantity IS
  'Quantidade comprada/reservada nesta encomenda (mínimo 1).';
