DROP FUNCTION IF EXISTS public.get_products_by_price_range(numeric, numeric, text, text, boolean, text, integer);

CREATE OR REPLACE FUNCTION public.get_products_by_price_range(
  p_min_price numeric DEFAULT 0,
  p_max_price numeric DEFAULT 999999,
  p_category text DEFAULT NULL,
  p_brand text DEFAULT NULL,
  p_in_stock_only boolean DEFAULT false,
  p_sort_by text DEFAULT 'popularity', 
  p_limit integer DEFAULT 20
)
RETURNS TABLE (
  product_id integer,
  product_name text,
  brand text,
  category text,
  price numeric,
  stock_qty integer,
  sales_this_month integer,
  warehouse_location text,
  created_at timestamp with time zone,
  value_score numeric 
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    e.product_id,
    e.product_name,
    e.brand,
    e.category,
    e.price,
    e.stock_qty,
    e.sales_this_month,
    e.warehouse_location,
    e.created_at,
    -- Value score: popularity + availability - price impact
    ROUND(
      (e.sales_this_month::numeric / NULLIF((SELECT MAX(sales_this_month) FROM products_table), 0) * 50) +
      (LEAST(e.stock_qty, 20)::numeric / 20 * 30) +
      ((p_max_price - e.price) / NULLIF(p_max_price, 0) * 20),
      2
    ) as value_score
  FROM public.products_table e
  WHERE 
    -- Price range filter
    e.price BETWEEN p_min_price AND p_max_price
    
    -- Category filter (optional)
    AND (p_category IS NULL OR e.category ILIKE '%' || p_category || '%')
    
    -- Brand filter (optional)
    AND (p_brand IS NULL OR e.brand ILIKE '%' || p_brand || '%')
    
    -- Stock filter (optional)
    AND (NOT p_in_stock_only OR e.stock_qty > 0)
    
  -- Dynamic sorting based on p_sort_by parameter
  ORDER BY 
    CASE 
      WHEN p_sort_by = 'popularity' THEN e.sales_this_month
      ELSE NULL
    END DESC NULLS LAST,
    
    CASE 
      WHEN p_sort_by = 'price_low' THEN e.price
      ELSE NULL
    END ASC NULLS LAST,
    
    CASE 
      WHEN p_sort_by = 'price_high' THEN e.price
      ELSE NULL
    END DESC NULLS LAST,
    
    CASE 
      WHEN p_sort_by = 'newest' THEN e.created_at
      ELSE NULL
    END DESC NULLS LAST,
    
    -- Default tiebreaker: popularity then price
    e.sales_this_month DESC,
    e.price ASC
    
  LIMIT p_limit;
END;
$$;