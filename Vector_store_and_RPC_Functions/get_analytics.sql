-- Drop existing function
DROP FUNCTION IF EXISTS public.get_analytics(text, text);

-- Create updated function
CREATE OR REPLACE FUNCTION public.get_analytics(
  p_brand text DEFAULT NULL,
  p_category text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_summary jsonb;
  v_by_brand jsonb;
  v_by_category jsonb;
  v_top_selling jsonb;
  v_low_stock jsonb;
BEGIN

  -- SUMMARY STATISTICS (WITH PROPER FILTERING)
  SELECT jsonb_build_object(
    'filter_applied', jsonb_build_object(
      'brand', p_brand,
      'category', p_category
    ),
    'total_products', COUNT(*),
    'total_inventory_value', ROUND(SUM(price * stock_qty), 2),
    'total_stock_units', SUM(stock_qty),
    'total_units_sold_this_month', SUM(sales_this_month),
    'total_sales_value_this_month', ROUND(SUM(sales_this_month * price), 2),
    'average_price', ROUND(AVG(price), 2),
    'low_stock_products', COUNT(*) FILTER (WHERE stock_qty < 10),
    'out_of_stock_products', COUNT(*) FILTER (WHERE stock_qty = 0),
    'products_with_high_sales', COUNT(*) FILTER (WHERE sales_this_month > 20)
  ) INTO v_summary
  FROM public.products_table
  WHERE 
    -- CRITICAL: Proper filtering logic
    (p_brand IS NULL OR brand ILIKE p_brand)
    AND (p_category IS NULL OR category ILIKE p_category);

  -- BY BRAND BREAKDOWN (WITHIN FILTERED DATASET)
  SELECT jsonb_agg(brand_stats ORDER BY total_sales DESC) INTO v_by_brand
  FROM (
    SELECT jsonb_build_object(
        'brand', brand,
        'product_count', COUNT(*),
        'total_stock', SUM(stock_qty),
        'total_sales_units', SUM(sales_this_month),
        'total_sales_value', ROUND(SUM(sales_this_month * price), 2),
        'total_inventory_value', ROUND(SUM(price * stock_qty), 2),
        'avg_price', ROUND(AVG(price), 2),
        'low_stock_count', COUNT(*) FILTER (WHERE stock_qty < 10)
      ) as brand_stats,
      SUM(sales_this_month) as total_sales
    FROM public.products_table
    WHERE 
      (p_brand IS NULL OR brand ILIKE p_brand)
      AND (p_category IS NULL OR category ILIKE p_category)
    GROUP BY brand
    HAVING COUNT(*) > 0  -- Only include brands with products
  ) brand_data;


  -- BY CATEGORY BREAKDOWN (WITHIN FILTERED DATASET)
  SELECT jsonb_agg(category_stats ORDER BY total_sales DESC) INTO v_by_category
  FROM (
    SELECT jsonb_build_object(
        'category', category,
        'product_count', COUNT(*),
        'total_stock', SUM(stock_qty),
        'total_sales_units', SUM(sales_this_month),
        'total_sales_value', ROUND(SUM(sales_this_month * price), 2),
        'total_inventory_value', ROUND(SUM(price * stock_qty), 2),
        'avg_price', ROUND(AVG(price), 2)
      ) as category_stats,
      SUM(sales_this_month) as total_sales
    FROM public.products_table
    WHERE 
      (p_brand IS NULL OR brand ILIKE p_brand)
      AND (p_category IS NULL OR category ILIKE p_category)
    GROUP BY category
    HAVING COUNT(*) > 0  -- Only include categories with products
  ) category_data;


  -- TOP SELLING PRODUCTS (WITHIN FILTERED DATASET)
  SELECT jsonb_agg(jsonb_build_object(
      'product_name', product_name,
      'brand', brand,
      'category', category,
      'sales_this_month', sales_this_month,
      'stock_qty', stock_qty,
      'price', price,
      'sales_value_this_month', ROUND(sales_this_month * price, 2)
    )) INTO v_top_selling
  FROM (
    SELECT product_name, brand, category, sales_this_month, stock_qty, price
    FROM public.products_table
    WHERE 
      (p_brand IS NULL OR brand ILIKE p_brand)
      AND (p_category IS NULL OR category ILIKE p_category)
    ORDER BY sales_this_month DESC
    LIMIT 10
  ) top_products;


  -- LOW STOCK PRODUCTS (WITHIN FILTERED DATASET)

  SELECT jsonb_agg(jsonb_build_object(
      'product_name', product_name,
      'brand', brand,
      'category', category,
      'stock_qty', stock_qty,
      'sales_this_month', sales_this_month,
      'price', price,
      'sales_value_this_month', ROUND(sales_this_month * price, 2),
      'urgency', CASE 
        WHEN stock_qty = 0 THEN 'OUT_OF_STOCK'
        WHEN stock_qty < 3 THEN 'CRITICAL'
        WHEN stock_qty < 10 THEN 'LOW'
        ELSE 'MODERATE'
      END
    )) INTO v_low_stock
  FROM (
    SELECT product_name, brand, category, stock_qty, sales_this_month, price
    FROM public.products_table
    WHERE 
      stock_qty < 10
      AND (p_brand IS NULL OR brand ILIKE p_brand)
      AND (p_category IS NULL OR category ILIKE p_category)
    ORDER BY stock_qty ASC, sales_this_month DESC
    LIMIT 20
  ) low_stock;

  -- RETURN COMBINED RESULTS
  RETURN jsonb_build_object(
    'summary', v_summary,
    'by_brand', COALESCE(v_by_brand, '[]'::jsonb),
    'by_category', COALESCE(v_by_category, '[]'::jsonb),
    'top_selling_products', COALESCE(v_top_selling, '[]'::jsonb),
    'low_stock_products', COALESCE(v_low_stock, '[]'::jsonb)
  );
END;
$$;
