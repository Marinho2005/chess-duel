export type CountryOption = { code: string; name: string }

const isoCodes = `AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW`.split(' ')

// Broadcasts usam códigos de federação FIDE (normalmente alpha-3), enquanto
// emoji de bandeira exige ISO alpha-2. Inclui as federações mais recorrentes
// no circuito internacional; códigos desconhecidos continuam sem bandeira.
const fideToIso2: Record<string, string> = {
  ARG: 'AR', ARM: 'AM', AUS: 'AU', AUT: 'AT', AZE: 'AZ', BEL: 'BE', BIH: 'BA',
  BLR: 'BY', BRA: 'BR', BUL: 'BG', CAN: 'CA', CHI: 'CL', CHN: 'CN', COL: 'CO',
  CRO: 'HR', CUB: 'CU', CZE: 'CZ', DEN: 'DK', EGY: 'EG', ENG: 'GB', ESP: 'ES',
  EST: 'EE', FIN: 'FI', FRA: 'FR', GEO: 'GE', GER: 'DE', GRE: 'GR', HUN: 'HU',
  INA: 'ID', IND: 'IN', IRI: 'IR', IRL: 'IE', ISR: 'IL', ITA: 'IT', JPN: 'JP',
  KAZ: 'KZ', LAT: 'LV', LTU: 'LT', MEX: 'MX', MGL: 'MN', NED: 'NL', NOR: 'NO',
  NZL: 'NZ', PAR: 'PY', PER: 'PE', PHI: 'PH', POL: 'PL', POR: 'PT', ROU: 'RO',
  RUS: 'RU', SCO: 'GB', SLO: 'SI', SRB: 'RS', SUI: 'CH', SVK: 'SK', SWE: 'SE',
  TUR: 'TR', UAE: 'AE', UKR: 'UA', URU: 'UY', USA: 'US', UZB: 'UZ', VEN: 'VE',
  VIE: 'VN', WLS: 'GB', RSA: 'ZA'
}

const displayNames = typeof Intl.DisplayNames === 'function'
  ? new Intl.DisplayNames(['pt-BR'], { type: 'region' })
  : null

export const countries: CountryOption[] = isoCodes
  .map(code => ({ code, name: displayNames?.of(code) || code }))
  .sort((a, b) => a.name.localeCompare(b.name, 'pt-BR'))

export function normalizeCountryCode(code?: string | null) {
  const normalized = code?.trim().toUpperCase() || ''
  if (/^[A-Z]{2}$/.test(normalized)) return normalized
  return fideToIso2[normalized] || ''
}

export function countryFlag(code?: string | null) {
  const normalized = normalizeCountryCode(code)
  return normalized
    ? String.fromCodePoint(...[...normalized].map(letter => 127397 + letter.charCodeAt(0)))
    : ''
}

export function countryFlagAssetUrl(code?: string | null) {
  const normalized = normalizeCountryCode(code)
  if (!normalized) return ''

  const codepoints = [...normalized]
    .map(letter => (127397 + letter.charCodeAt(0)).toString(16))
    .join('-')

  return `https://cdn.jsdelivr.net/gh/jdecked/twemoji@17.0.3/assets/svg/${codepoints}.svg`
}

export function countryName(code?: string | null) {
  const normalized = normalizeCountryCode(code)
  return normalized ? displayNames?.of(normalized) || normalized : ''
}
