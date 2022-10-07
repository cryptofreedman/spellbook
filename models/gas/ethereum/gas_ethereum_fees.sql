{{ config(
    alias = 'fees',
    partition_by = ['block_date'],
    materialized = 'incremental',
    file_format = 'delta',
    incremental_strategy = 'merge',
    unique_key = ['block_time','tx_hash','tx_amount_native']
    )
}}

SELECT 
     'ethereum' as blockchain,
     date_trunc('day', block_time) AS block_date,
     block_time,
     block_number,
     txns.hash AS tx_hash,
     'ETH' as native_token_symbol,
     value/1e18 AS tx_amount_native,
     value/1e18 * p.price AS tx_amount_usd,
     CASE WHEN type = 'Legacy' THEN (gas_price * txns.gas_used)/1e18
          WHEN type = 'DynamicFee' THEN ((base_fee_per_gas + priority_fee_per_gas) * txns.gas_used)/1e18 
          END AS tx_fee_native, 
     CASE WHEN type = 'Legacy' THEN (gas_price * txns.gas_used)/1e18 * p.price 
          WHEN type = 'DynamicFee' THEN ((base_fee_per_gas + priority_fee_per_gas) * txns.gas_used)/1e18 * p.price 
          END AS tx_fee_usd,
     ((base_fee_per_gas) * txns.gas_used)/1e18 AS burned_native, 
     (((base_fee_per_gas) * txns.gas_used)/1e18) * p.price AS burned_usd,
     ((max_fee_per_gas - priority_fee_per_gas - base_fee_per_gas) * txns.gas_used)/1e18 AS tx_savings_native,
     (((max_fee_per_gas - priority_fee_per_gas - base_fee_per_gas) * txns.gas_used)/1e18) * p.price AS tx_savings_usd,
     miner AS validator, -- or block_proposer since Proposer Builder Separation (PBS) happened ?
     max_fee_per_gas / 1e9 AS max_fee_gwei,
     max_fee_per_gas / 1e18 * p.price AS max_fee_usd,
     base_fee_per_gas / 1e9 AS base_fee_gwei,
     base_fee_per_gas / 1e18 * p.price AS base_fee_usd,
     priority_fee_per_gas / 1e9 AS priority_fee_gwei,
     priority_fee_per_gas / 1e18 * p.price AS priority_fee_usd,
     gas_price /1e9 AS gas_price_gwei,
     gas_price / 1e18 * p.price AS gas_price_usd,
     txns.gas_used,
     txns.gas_limit,
     txns.gas_used / txns.gas_limit * 100 AS gas_usage_percent,
     difficulty,
     type AS transaction_type
FROM ethereum.transactions txns
JOIN ethereum.blocks blocks ON blocks.number = txns.block_number
{% if is_incremental() %}
AND block_time >= date_trunc("day", now() - interval '1 week')
AND blocks.time >= date_trunc("day", now() - interval '1 week')
{% endif %}
LEFT JOIN prices.usd p ON p.minute = date_trunc('minute', block_time)
AND p.blockchain = 'ethereum'
AND p.symbol = 'WETH'
{% if is_incremental() %}
AND p.minute >= date_trunc("day", now() - interval '1 week')
WHERE block_time >= date_trunc("day", now() - interval '1 week')
AND blocks.time >= date_trunc("day", now() - interval '1 week')
AND p.minute >= date_trunc("day", now() - interval '1 week')
{% endif %}