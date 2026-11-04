---
type: regex
target: trace
pattern: '"name":"(?:Write|Edit)","input":\{"file_path":"[^"]*test[^"]*\.js"[^\n]*?(?:\\[nt]|[^A-Za-z0-9_$])(?:test|it)\(\\*[''"`]SEC-\d+-\d+(?:(?!(?:\\[nt]|[^A-Za-z0-9_$])(?:test|it)\()[^\n])*?todo:(?:(?!(?:\\[nt]|[^A-Za-z0-9_$])(?:test|it)\()[^\n])*?(?:getRoom(?:(?!(?:\\[nt]|[^A-Za-z0-9_$])(?:test|it)\()[^\n])*?clinicB|clinicB(?:(?!(?:\\[nt]|[^A-Za-z0-9_$])(?:test|it)\()[^\n])*?getRoom)'
match: not_contains
---
