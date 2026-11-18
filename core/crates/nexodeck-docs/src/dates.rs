//! Fechas en el formato de los diarios: "15-sep" en los encabezados y
//! "15 de septiembre de 2026" en la linea de actualizacion.

const MONTHS_SHORT: [&str; 12] = [
    "ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic",
];
const MONTHS_LONG: [&str; 12] = [
    "enero",
    "febrero",
    "marzo",
    "abril",
    "mayo",
    "junio",
    "julio",
    "agosto",
    "septiembre",
    "octubre",
    "noviembre",
    "diciembre",
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SpanishDate {
    pub year: i16,
    pub month: u8,
    pub day: u8,
}

impl SpanishDate {
    /// Hoy en hora **local**: pasada la medianoche en Colombia, en UTC ya seria
    /// otro dia y el encabezado del diario quedaria con la fecha equivocada.
    pub fn today() -> Self {
        Self::from_civil(jiff::Zoned::now().date())
    }

    /// El dia local de un instante: el de una propuesta ya generada, por
    /// ejemplo, que se aprueba al dia siguiente con su encabezado de ayer.
    pub fn from_timestamp(timestamp: jiff::Timestamp) -> Self {
        Self::from_civil(timestamp.to_zoned(jiff::tz::TimeZone::system()).date())
    }

    /// `YYYY-MM-DD`, que es como lo manda Claude Code.
    pub fn parse_iso(text: &str) -> Option<Self> {
        let date: jiff::civil::Date = text.trim().parse().ok()?;
        Some(Self::from_civil(date))
    }

    fn from_civil(date: jiff::civil::Date) -> Self {
        SpanishDate {
            year: date.year(),
            month: date.month() as u8,
            day: date.day() as u8,
        }
    }

    /// `15-sep`.
    pub fn short(&self) -> String {
        format!("{}-{}", self.day, MONTHS_SHORT[usize::from(self.month - 1)])
    }

    /// `2026-09-15`: el nombre de una nota diaria.
    pub fn iso(&self) -> String {
        format!("{:04}-{:02}-{:02}", self.year, self.month, self.day)
    }

    /// `15 de septiembre de 2026`.
    pub fn long(&self) -> String {
        format!(
            "{} de {} de {}",
            self.day,
            MONTHS_LONG[usize::from(self.month - 1)],
            self.year
        )
    }
}

/// `true` si el texto tiene la forma `15-sep`.
pub(crate) fn is_short_date(text: &str) -> bool {
    let Some((day, month)) = text.split_once('-') else {
        return false;
    };
    !day.is_empty()
        && day.len() <= 2
        && day.bytes().all(|b| b.is_ascii_digit())
        && MONTHS_SHORT.contains(&month)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_like_the_existing_journals() {
        let date = SpanishDate::parse_iso("2026-09-05").unwrap();
        assert_eq!(date.short(), "5-sep");
        assert_eq!(date.long(), "5 de septiembre de 2026");
    }

    #[test]
    fn recognises_a_short_date_and_nothing_else() {
        assert!(is_short_date("14-sep"));
        assert!(is_short_date("1-ene"));
        assert!(!is_short_date("14-sept"));
        assert!(!is_short_date("sep-14"));
        assert!(!is_short_date("2026-09-14"));
    }
}
