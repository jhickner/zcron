# zcron

Command repeater. Cron-like syntax, but includes seconds.

Order of arguments is:
1. Seconds, 0-59
2. Minutes, 0-59
3. Hours, 0-23
4. Days, 1-31
5. Months, 1-12
6. Weekdays, 0-6, 0 is Sunday

Each argument can be:
- '*' indicates any value
- a single value, e.g. 12
- a range, e.g. 4-7 
- '*' or a range with an optional step:
    - */5 - every 5th
    - 25-40/10 - every 10th from 25 while <= 40, so 25, 35

Examples:
```
# every 5 seconds say hello
*/5 say hello

# every 5 seconds on tuesday say hello
*/5 * * * 2 say hello
```
