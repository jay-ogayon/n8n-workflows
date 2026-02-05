DROP FUNCTION IF EXISTS public.semantic_search(vector, int, jsonb);

CREATE OR REPLACE FUNCTION public.semantic_search(
  query_embedding vector(1536),
  match_count int DEFAULT 10,
  filter jsonb DEFAULT '{}'
)
RETURNS TABLE (
  id integer,
  content text,
  metadata jsonb,
  similarity float
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    e.product_id as id,
    (e.product_name || ' ' || e.brand || ' ' || e.category || ' ' || COALESCE(e.description, '')) as content,
    jsonb_build_object(
      'product_id', e.product_id,
      'product_name', e.product_name,
      'brand', e.brand,
      'category', e.category,
      'price', e.price,
      'stock_qty', e.stock_qty,
      'warehouse_location', e.warehouse_location,
      'sales_this_month', e.sales_this_month
    ) as metadata,
    1 - (e.description_embedding <=> query_embedding) as similarity
  FROM products_table e
  WHERE e.description_embedding IS NOT NULL
    AND (filter->>'brand' IS NULL OR e.brand = (filter->>'brand'))
    AND (filter->>'category' IS NULL OR e.category = (filter->>'category'))
  ORDER BY e.description_embedding <=> query_embedding
  LIMIT match_count;
END;
$$;
