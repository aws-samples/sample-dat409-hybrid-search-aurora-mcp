# DAT409 Lab 1 - Solutions Guide for Instructors

## Overview

This guide contains complete solutions for the three TODO sections in the student notebook. Use this to:
- Help students who are stuck
- Verify correct implementations
- Understand common mistakes

---

## TODO 1: Fuzzy Search Solution

### Complete Implementation

```python
def fuzzy_search(query: str, limit: int = 10) -> list[dict]:
    """PostgreSQL Trigram Search for typo tolerance"""
    with psycopg.connect(
        host=dbhost, port=dbport, user=dbuser,
        password=dbpass, autocommit=True
    ) as conn:
        conn.execute("SET pg_trgm.similarity_threshold = 0.1;")
        
        results = conn.execute("""
            SELECT 
                "productId",
                product_description,
                category_name,
                price,
                stars,
                reviews,
                imgurl as "imgUrl",
                similarity(lower(product_description), lower(%s)) as sim
            FROM bedrock_integration.product_catalog
            WHERE lower(product_description) %% lower(%s)
            ORDER BY sim DESC
            LIMIT %s;
        """, (query, query, limit)).fetchall()
        
        return [{
            'productId': r[0],
            'description': r[1][:200] + '...',
            'category': r[2],
            'price': float(r[3]) if r[3] else 0,
            'stars': float(r[4]) if r[4] else 0,
            'reviews': int(r[5]) if r[5] else 0,
            'imgUrl': r[6],
            'score': float(r[7]) if r[7] else 0,
            'method': 'Fuzzy'
        } for r in results]
```

### Key Points Students Miss

1. **Case sensitivity**: Must use `lower()` on both sides of comparison
2. **Double %% operator**: Students often use single % (modulo) instead of %% (similarity)
3. **Parameter binding**: Need to pass query twice (once for similarity, once for WHERE)
4. **Threshold**: The 0.1 threshold means 10% trigram overlap is required

### Common Errors

**Error**: `operator does not exist: text %% text`
**Solution**: Ensure pg_trgm extension is installed

**Error**: No results returned
**Solution**: Threshold may be too high; try 0.1 or lower

---

## TODO 2: Semantic Search Solution

### Complete Implementation

```python
def semantic_search(query: str, limit: int = 10) -> list[dict]:
    """Semantic Search using Cohere embeddings"""
    
    query_embedding = generate_embedding(query, "search_query")
    if not query_embedding:
        return []
    
    with psycopg.connect(
        host=dbhost, port=dbport, user=dbuser,
        password=dbpass, autocommit=True
    ) as conn:
        register_vector(conn)
        
        results = conn.execute("""
            SELECT 
                "productId",
                product_description,
                category_name,
                price,
                stars,
                reviews,
                imgurl as "imgUrl",
                1 - (embedding <=> %s::vector) as similarity
            FROM bedrock_integration.product_catalog
            WHERE embedding IS NOT NULL
            ORDER BY embedding <=> %s::vector
            LIMIT %s;
        """, (query_embedding, query_embedding, limit)).fetchall()
        
        return [{
            'productId': r[0],
            'description': r[1][:200] + '...',
            'category': r[2],
            'price': float(r[3]) if r[3] else 0,
            'stars': float(r[4]) if r[4] else 0,
            'reviews': int(r[5]) if r[5] else 0,
            'imgUrl': r[6],
            'score': float(r[7]) if r[7] else 0,
            'method': 'Semantic'
        } for r in results]
```

### Key Points Students Miss

1. **Distance vs Similarity**: `<=>` returns distance (lower is better), need to convert with `1 - distance`
2. **Type casting**: Must cast to `::vector` type
3. **Null filtering**: Critical to filter `WHERE embedding IS NOT NULL`
4. **Parameter duplication**: Need to pass embedding twice (SELECT and ORDER BY)
5. **Register vector**: Must call `register_vector(conn)` before using vector operations

### Common Errors

**Error**: `operator does not exist: vector <=> double precision[]`
**Solution**: Cast query embedding to vector: `%s::vector`

**Error**: Very slow query (>5 seconds)
**Solution**: Check if HNSW index exists on embedding column

**Error**: Unexpected results (random products)
**Solution**: Likely forgot to filter `WHERE embedding IS NOT NULL`

---

## TODO 3: Hybrid RRF Search Solution

### Complete Implementation

```python
def hybrid_search_rrf(
    query: str,
    k: int = 60,
    limit: int = 10
) -> list[dict]:
    """Hybrid Search using Reciprocal Rank Fusion (RRF)"""
    
    query_embedding = generate_embedding(query, "search_query")
    if not query_embedding:
        return []
    
    with psycopg.connect(
        host=dbhost, port=dbport, user=dbuser,
        password=dbpass, autocommit=True
    ) as conn:
        register_vector(conn)
        
        results = conn.execute("""
            WITH semantic_search AS (
                SELECT 
                    "productId",
                    product_description,
                    category_name,
                    price,
                    stars,
                    reviews,
                    imgurl,
                    RANK() OVER (ORDER BY embedding <=> %s::vector) AS rank
                FROM bedrock_integration.product_catalog
                WHERE embedding IS NOT NULL
                ORDER BY embedding <=> %s::vector
                LIMIT 20
            ),
            keyword_search AS (
                SELECT 
                    "productId",
                    product_description,
                    category_name,
                    price,
                    stars,
                    reviews,
                    imgurl,
                    RANK() OVER (ORDER BY ts_rank_cd(to_tsvector('english', product_description), query) DESC) AS rank
                FROM bedrock_integration.product_catalog, plainto_tsquery('english', %s) query
                WHERE to_tsvector('english', product_description) @@ query
                ORDER BY ts_rank_cd(to_tsvector('english', product_description), query) DESC
                LIMIT 20
            )
            SELECT
                COALESCE(s."productId", k."productId") AS product_id,
                COALESCE(s.product_description, k.product_description) AS description,
                COALESCE(s.category_name, k.category_name) AS category,
                COALESCE(s.price, k.price) AS price,
                COALESCE(s.stars, k.stars) AS stars,
                COALESCE(s.reviews, k.reviews) AS reviews,
                COALESCE(s.imgurl, k.imgurl) AS imgurl,
                (COALESCE(1.0 / (%s + s.rank), 0.0) + COALESCE(1.0 / (%s + k.rank), 0.0)) AS rrf_score
            FROM semantic_search s
            FULL OUTER JOIN keyword_search k ON s."productId" = k."productId"
            ORDER BY rrf_score DESC
            LIMIT %s
        """, (query_embedding, query_embedding, query, k, k, limit)).fetchall()
        
        return [{
            'productId': r[0],
            'description': r[1][:200] + '...',
            'category': r[2],
            'price': float(r[3]) if r[3] else 0,
            'stars': float(r[4]) if r[4] else 0,
            'reviews': int(r[5]) if r[5] else 0,
            'imgUrl': r[6],
            'score': float(r[7]) if r[7] else 0,
            'method': 'Hybrid-RRF'
        } for r in results]
```

### Key Points Students Miss

1. **RANK() vs ROW_NUMBER()**: Either works, but RANK() handles ties better
2. **Column name quoting**: `"productId"` must be quoted due to mixed case
3. **COALESCE for nulls**: Essential when using FULL OUTER JOIN
4. **Default rank of 1000**: For missing items, use high rank (not 0) so they contribute minimally
5. **k parameter**: Pass k twice (once per method) in the RRF calculation

### Common Errors

**Error**: `column "productid" does not exist`
**Solution**: Use quoted identifier: `"productId"` (capital I)

**Error**: Incorrect RRF scores (all same or zero)
**Solution**: Check COALESCE logic and ensure you're summing scores from both methods

**Error**: Only getting results from one method
**Solution**: Use FULL OUTER JOIN, not INNER JOIN or LEFT JOIN

**Error**: SQL syntax error near RANK()
**Solution**: Ensure OVER clause is present: `RANK() OVER (ORDER BY ...)`

---

## Teaching Tips

### Time Management

- **5 minutes**: Setup cells (students just run)
- **15 minutes**: Three TODOs (5 min each)
- **5 minutes**: Testing and widget experimentation

### When Students Get Stuck

**TODO 1 (Fuzzy)**: This is the easiest. If stuck for >3 minutes, show them the similarity() function syntax directly.

**TODO 2 (Semantic)**: Most confusion is around distance vs similarity. Draw on whiteboard: distance=0.2 → similarity=0.8

**TODO 3 (RRF)**: This is complex. If stuck, provide the CTE structure and have them just complete the RRF score calculation.

### Common Questions

**Q**: "Why do we pass query twice in each SQL?"
**A**: "Once for the SELECT (calculate score), once for WHERE/ORDER BY (filter/sort). PostgreSQL doesn't reuse the calculation."

**Q**: "Why is RRF score so small (0.02) compared to semantic (0.85)?"
**A**: "RRF is rank-based, not similarity-based. Lower numbers are normal. What matters is relative ordering."

**Q**: "Can I use INNER JOIN instead of FULL OUTER JOIN?"
**A**: "Try it! You'll lose products that only appear in one method. FULL OUTER JOIN gives you the union."

### Extension Challenges (for fast finishers)

1. Add fuzzy search to the RRF query (3 methods instead of 2)
2. Implement MinMax normalization for weighted fusion
3. Add category filtering to limit search to specific product types
4. Tune the similarity threshold and observe impact on fuzzy results

---

## Verification Script

Run this to quickly verify student implementations:

```python
# Quick verification
test_queries = [
    ("wireles hedphones", fuzzy_search),
    ("gift for coffee lover", semantic_search),
    ("affordable noise canceling under 200", hybrid_search_rrf)
]

for query, func in test_queries:
    try:
        results = func(query, 3)
        status = "✅" if results else "⚠️ "
        print(f"{status} {func.__name__}: {len(results)} results")
    except Exception as e:
        print(f"❌ {func.__name__}: {str(e)[:50]}")
```

---

## Expected Results

### TODO 1 Test: "wireles hedphones"
- Should find: Wireless headphones products
- Score range: 0.15 - 0.35 (trigram overlap)
- Top result should contain "wireless" and "headphone"

### TODO 2 Test: "gift for coffee lover"
- Should find: Coffee mugs, thermoses, coffee makers
- Score range: 0.65 - 0.85 (semantic similarity)
- Should NOT just be exact keyword matches

### TODO 3 Test: "affordable noise canceling under 200"
- Should find: Budget ANC headphones
- RRF score range: 0.01 - 0.04 (rank-based)
- Should combine semantic + keyword effectively

---

## Instructor Notes File Location

Place the complete notebook (with solutions) in:
```
lab1-hybrid-search/solutions/dat409-hybrid-search-notebook-COMPLETE.ipynb
```

Students receive:
```
lab1-hybrid-search/dat409-hybrid-search-notebook.ipynb  (TODO version)
```
