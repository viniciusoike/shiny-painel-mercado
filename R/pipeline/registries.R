# Copyright (c) 2024 Vinicius Oike Reginatto
# SPDX-License-Identifier: MIT

# Series registries -----------------------------------------------------------

RPPI_SERIES_REGISTRY <- tibble::tribble(
  ~source   , ~frequency , ~kind         , ~scale     , ~seasonal , ~deflator     ,
  "FipeZap" , "month"    , "price_index" , "fraction" , "stl"     , NA_character_ ,
  "IGMI-R"  , "month"    , "price_index" , "fraction" , "stl"     , NA_character_ ,
  "IQAIW"   , "month"    , "price_index" , "fraction" , "stl"     , NA_character_ ,
  "IVAR"    , "month"    , "price_index" , "fraction" , "stl"     , NA_character_ ,
  "IVG-R"   , "month"    , "price_index" , "fraction" , "stl"     , NA_character_
)

BCB_SERIES_REGISTRY <- tibble::tribble(
  ~series                                             , ~code  ,
  "igpm"                                              ,   189L ,
  "incc"                                              ,   192L ,
  "selic"                                             ,   432L ,
  "ipca"                                              ,   433L ,
  "taxa_tr"                                           , 13421L ,
  "fimob_pj_mercado"                                  , 20690L ,
  "fimob_pj_regulada"                                 , 20691L ,
  "fimob_pj_total"                                    , 20692L ,
  "fimob_pf_mercado"                                  , 20702L ,
  "fimob_pf_regulada"                                 , 20703L ,
  "fimob_pf_total"                                    , 20704L ,
  "taxa_fimob_total"                                  , 20756L ,
  "taxa_fimob_pj_total"                               , 20763L ,
  "taxa_fimob_pf_total"                               , 20774L ,
  "prazo_fimob_pj_total"                              , 20902L ,
  "prazo_fimob_pf_total"                              , 20914L ,
  "atraso_fimob_pj_mercado"                           , 21058L ,
  "atraso_fimob_pj_regulado"                          , 21059L ,
  "atraso_fimob_pj_total"                             , 21060L ,
  "atraso_fimob_pf_mercado"                           , 21070L ,
  "atraso_fimob_pf_regulado"                          , 21071L ,
  "atraso_fimob_pf_total"                             , 21072L ,
  "inad_credito_direcionado_total"                    , 21132L ,
  "inad_credito_direcionado_pj"                       , 21133L ,
  "inad_credito_direcionado_pj_fimob"                 , 21139L ,
  "inad_credito_direcionado_pf"                       , 21145L ,
  "inad_credito_direcionado_pf_fimob"                 , 21151L ,
  "ivgr"                                              , 21340L ,
  "icc"                                               , 25351L ,
  "icc_direcionado"                                   , 25357L ,
  "icc_direcionado_pf"                                , 25359L ,
  "icc_fimob_market_pf"                               , 27713L ,
  "icc_fimob_regulated_pf"                            , 27714L ,
  "icc_fimob"                                         , 27715L ,
  "comprometimento_renda_juros"                       , 29033L ,
  "comprometimento_renda_servico_total"               , 29034L ,
  "comprometimento_renda_servico_exceto_habitacional" , 29035L ,
  "comprometimento_renda_amort"                       , 29036L ,
  "endividamento_total"                               , 29037L ,
  "endividamento_exceto_habitacional"                 , 29038L
) |>
  dplyr::mutate(
    frequency = "month",
    kind = dplyr::case_when(
      .data$series %in% c("ipca", "igpm", "incc", "taxa_tr") ~
        "rate_change",
      .data$series == "ivgr" ~ "price_index",
      startsWith(.data$series, "prazo_") ~ "duration",
      startsWith(.data$series, "fimob_") ~ "monetary",
      TRUE ~ "rate"
    ),
    scale = dplyr::if_else(
      .data$kind %in% c("rate", "rate_change"),
      "percent",
      "level"
    ),
    seasonal = "source",
    deflator = dplyr::if_else(.data$kind == "monetary", "ipca", NA_character_)
  )

ABECIP_SERIES_REGISTRY <- tibble::tribble(
  ~dataset       , ~series                 , ~kind      , ~unit        , ~scale  , ~seasonal , ~deflator     ,
  "abecip_units" , "units_construction"    , "flow"     , "units"      , "level" , "none"    , NA_character_ ,
  "abecip_units" , "units_acquisition"     , "flow"     , "units"      , "level" , "none"    , NA_character_ ,
  "abecip_units" , "units_total"           , "flow"     , "units"      , "level" , "none"    , NA_character_ ,
  "abecip_units" , "currency_construction" , "monetary" , "R$ million" , "level" , "none"    , "ipca"        ,
  "abecip_units" , "currency_acquisition"  , "monetary" , "R$ million" , "level" , "none"    , "ipca"        ,
  "abecip_units" , "currency_total"        , "monetary" , "R$ million" , "level" , "none"    , "ipca"        ,
  "abecip_sbpe"  , "sbpe_netflow"          , "monetary" , "R$"         , "level" , "none"    , "ipca"        ,
  "abecip_sbpe"  , "sbpe_stock"            , "monetary" , "R$"         , "level" , "none"    , "ipca"
)

ABRAINC_SERIES_REGISTRY <- tibble::tribble(
  ~category    , ~kind      , ~unit        , ~scale  , ~seasonal , ~deflator     ,
  "new_units"  , "flow"     , "units"      , "level" , "none"    , NA_character_ ,
  "sold"       , "flow"     , "units"      , "level" , "none"    , NA_character_ ,
  "delivered"  , "flow"     , "units"      , "level" , "none"    , NA_character_ ,
  "distratado" , "flow"     , "units"      , "level" , "none"    , NA_character_ ,
  "supply"     , "stock"    , "units"      , "level" , "none"    , NA_character_ ,
  "value"      , "monetary" , "R$ million" , "level" , "none"    , "ipca"
)

SECOVI_SERIES_REGISTRY <- tibble::tribble(
  ~variable      , ~name                        , ~kind      , ~unit        , ~scale    , ~seasonal , ~deflator     ,
  "launches"     , "unidades"                   , "flow"     , "units"      , "level"   , "none"    , NA_character_ ,
  "launches"     , "vgv_potencial_em_r_milhoes" , "monetary" , "R$ million" , "level"   , "none"    , "ipca"        ,
  "sales"        , "unidades"                   , "flow"     , "units"      , "level"   , "none"    , NA_character_ ,
  "sales"        , "vgv_em_milhoes_de_r"        , "monetary" , "R$ million" , "level"   , "none"    , "ipca"        ,
  "sales"        , "vso_vendas_sobre_oferta"    , "rate"     , "%"          , "percent" , "none"    , NA_character_ ,
  "supply"       , "saldo_unidades"             , "stock"    , "units"      , "level"   , "none"    , NA_character_ ,
  "sales_1rooms" , "unidades"                   , "flow"     , "units"      , "level"   , "none"    , NA_character_ ,
  "sales_2rooms" , "unidades"                   , "flow"     , "units"      , "level"   , "none"    , NA_character_ ,
  "sales_3rooms" , "unidades"                   , "flow"     , "units"      , "level"   , "none"    , NA_character_ ,
  "sales_4rooms" , "unidades"                   , "flow"     , "units"      , "level"   , "none"    , NA_character_
)

# BCB activity registry -------------------------------------------------------

SGS_ATIVIDADE <- tibble::tribble(
  ~series                      , ~code , ~label                                              , ~unit         , ~sa_source , ~kind   , ~group     ,
  "pnad_ocupados"              , 24379 , "Pessoas Ocupadas (PNAD Contínua)"                  , "mil pessoas" , FALSE      , "level" , "trabalho" ,
  "pnad_forca_trabalho"        , 24378 , "Força de Trabalho (PNAD Contínua)"                 , "mil pessoas" , FALSE      , "level" , "trabalho" ,
  "pnad_desocupacao"           , 24369 , "Taxa de Desocupação (PNAD Contínua)"               , "%"           , FALSE      , "rate"  , "trabalho" ,
  "emprego_formal"             , 28763 , "Estoque de Empregos Formais — Total"               , "pessoas"     , FALSE      , "level" , "trabalho" ,
  "emprego_formal_construcao"  , 28770 , "Estoque de Empregos Formais — Construção"          , "pessoas"     , FALSE      , "level" , "trabalho" ,
  "massa_rendimento"           , 28545 , "Massa de Rendimento Real Habitual"                 , "R$ milhões"  , FALSE      , "level" , "renda"    ,
  "rendimento_medio"           , 24382 , "Rendimento Médio Real Habitual"                    , "R$"          , FALSE      , "level" , "renda"    ,
  "renda_disponivel"           , 29027 , "Renda Disponível das Famílias — Massa"             , "R$ milhões"  , TRUE       , "level" , "renda"    ,
  "ipi_geral"                  , 28503 , "Produção Industrial — Geral"                       , "índice"      , TRUE       , "level" , "producao" ,
  "ipi_construcao"             , 28511 , "Produção Industrial — Insumos da Construção Civil" , "índice"      , TRUE       , "level" , "producao" ,
  "ipi_duraveis"               , 28509 , "Produção Industrial — Bens de Consumo Duráveis"    , "índice"      , TRUE       , "level" , "producao" ,
  "ibc_br"                     , 24364 , "IBC-Br — Atividade Econômica"                      , "índice"      , TRUE       , "level" , "producao" ,
  "varejo"                     , 28473 , "Volume de Vendas no Varejo — Total"                , "índice"      , TRUE       , "level" , "producao" ,
  "varejo_material_construcao" , 28484 , "Volume de Vendas — Material de Construção"         , "índice"      , TRUE       , "level" , "producao" ,
  "pms_servicos"               , 23982 , "Volume de Serviços (PMS) — Total"                  , "índice"      , FALSE      , "level" , "producao"
) |>
  dplyr::mutate(
    source = "bcb_sgs",
    frequency = "month",
    scale = dplyr::if_else(.data$kind == "rate", "percent", "level"),
    seasonal = dplyr::if_else(.data$sa_source, "source", "seats"),
    deflator = NA_character_
  )

# Dataset registry ------------------------------------------------------------

SOURCE_REGISTRY <- list(
  rppi = list(
    provider = "realestatebr",
    dataset = "rppi",
    table = "all",
    prep = prep_rppi
  ),
  abecip_sbpe = list(
    provider = "realestatebr",
    dataset = "abecip",
    table = "sbpe",
    prep = prep_abecip_sbpe
  ),
  abecip_units = list(
    provider = "realestatebr",
    dataset = "abecip",
    table = "units",
    prep = prep_abecip_units
  ),
  abrainc = list(
    provider = "realestatebr",
    dataset = "abrainc",
    table = "indicator",
    prep = prep_abrainc
  ),
  bcb_series = list(
    provider = "realestatebr",
    dataset = "bcb_series",
    table = "core",
    prep = prep_bcb_series
  ),
  secovi = list(
    provider = "realestatebr",
    dataset = "secovi",
    table = "all",
    prep = prep_secovi
  ),
  bcb_selic = list(
    provider = "GetBCBData",
    fetch = fetch_bcb_selic,
    prep = prep_bcb_selic
  ),
  bcb_activity = list(
    provider = "GetBCBData",
    fetch = fetch_bcb_activity,
    prep = prep_bcb_activity
  )
)
