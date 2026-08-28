use std::{collections::HashMap, sync::OnceLock};

use regex::Regex;

use crate::OutlineItem;

pub fn parse(relative_path: &str, source: &str) -> Vec<OutlineItem> {
    static EXPRESSION: OnceLock<Regex> = OnceLock::new();
    let expression = EXPRESSION.get_or_init(|| {
        Regex::new(r"\\(part|chapter|section|subsection|subsubsection|paragraph)\*?\s*\{([^}]*)\}")
            .expect("valid outline regex")
    });
    let levels: HashMap<&str, u8> = [
        ("part", 0),
        ("chapter", 1),
        ("section", 2),
        ("subsection", 3),
        ("subsubsection", 4),
        ("paragraph", 5),
    ]
    .into_iter()
    .collect();
    expression
        .captures_iter(source)
        .filter_map(|capture| {
            let matched = capture.get(0)?;
            let command = capture.get(1)?.as_str();
            let title = capture.get(2)?.as_str().trim();
            let line = source[..matched.start()]
                .bytes()
                .filter(|byte| *byte == b'\n')
                .count()
                + 1;
            Some(OutlineItem {
                relative_path: relative_path.to_owned(),
                line,
                title: title.to_owned(),
                level: *levels.get(command).unwrap_or(&2),
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_sections_with_lines() {
        let result = parse(
            "main.tex",
            "intro\n\\section{Methods}\ntext\n\\subsection*{Proof}",
        );
        assert_eq!(result.len(), 2);
        assert_eq!(result[0].line, 2);
        assert_eq!(result[1].level, 3);
    }
}
