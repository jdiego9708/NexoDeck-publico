//! Registro mínimo por la salida de error, con marca de hora UTC.
//!
//! **Nunca se registra el contenido de una petición ni de una respuesta** (prompts y generaciones
//! pueden llevar código o datos privados): solo qué clave, qué modelo, qué estado y cuánto tardó.

use std::time::{SystemTime, UNIX_EPOCH};

/// Fecha y hora UTC (`AAAA-MM-DD HH:MM:SSZ`) a partir de segundos desde el epoch. Se calcula a
/// mano (algoritmo de fechas civiles de Howard Hinnant) para no arrastrar una dependencia de
/// calendario solo por esto.
pub fn utc_timestamp(unix_seconds: u64) -> String {
    let days = (unix_seconds / 86_400) as i64;
    let seconds_of_day = unix_seconds % 86_400;

    let shifted = days + 719_468;
    let era = shifted.div_euclid(146_097);
    let day_of_era = shifted.rem_euclid(146_097);
    let year_of_era = (day_of_era - day_of_era / 1_460 + day_of_era / 36_524 - day_of_era / 146_096) / 365;
    let day_of_year = day_of_era - (365 * year_of_era + year_of_era / 4 - year_of_era / 100);
    let month_index = (5 * day_of_year + 2) / 153;
    let day = day_of_year - (153 * month_index + 2) / 5 + 1;
    let month = if month_index < 10 { month_index + 3 } else { month_index - 9 };
    let year = year_of_era + era * 400 + i64::from(month <= 2);

    format!(
        "{year:04}-{month:02}-{day:02} {:02}:{:02}:{:02}Z",
        seconds_of_day / 3_600,
        seconds_of_day % 3_600 / 60,
        seconds_of_day % 60
    )
}

/// Segundos desde el epoch, ahora.
pub fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|elapsed| elapsed.as_secs())
        .unwrap_or(0)
}

pub fn line(message: &str) {
    eprintln!("[{}] {message}", utc_timestamp(now_unix()));
}

#[cfg(test)]
mod tests {
    use super::utc_timestamp;

    #[test]
    fn formats_known_instants() {
        assert_eq!(utc_timestamp(0), "1970-01-01 00:00:00Z");
        assert_eq!(utc_timestamp(1_000_000_000), "2001-09-09 01:46:40Z");
        // Año bisiesto: 29 de febrero de 2024.
        assert_eq!(utc_timestamp(1_709_164_800), "2024-02-29 00:00:00Z");
    }
}
