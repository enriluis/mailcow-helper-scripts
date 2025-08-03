# 📫 Mailcow Alias Synchronization via Tags (Dynamic SQL Automation)

This project automates alias management in [Mailcow](https://mailcow.email/) by syncing group-based alias addresses with user accounts based on shared tag configurations. It uses **stored procedures** and **triggers** in MariaDB to ensure all alias entries reflect the latest tag associations.

---

## 💡 Problem & Motivation

In Mailcow, you cannot create an alias address that matches an existing mailbox address (e.g., `luis@example-mail.org` cannot be alias of `henrik@example-mail.org`). This restriction complicates group-level email routing.

To solve this, we:
- Create aliases like `finance_alias@example-mail.org`
- Dynamically populate their `goto` field with all mailboxes tagged as `finance`
- Keep alias definitions synchronized every time tags are added, modified, or removed

---

## 🗂 Database Schema Overview

### `tags_mailbox`
Stores mappings between user accounts and descriptive tags.

| tag_name     | username                 |
|--------------|--------------------------|
| finance      | alice@example-mail.org   |
| finance      | bob@example-mail.org     |

---

### `alias`
Mailcow’s native alias table, containing forwarding definitions.

| address                    | goto                                        | domain           |
|---------------------------|---------------------------------------------|------------------|
| finance_alias@example-mail.org | alice@example-mail.org,bob@example-mail.org | example-mail.org |

---

## ⚙️ Stored Procedure

Creates or updates alias entries based on current tag mappings.

```sql
DELIMITER $$
s
CREATE PROCEDURE sync_aliases_from_tags()
BEGIN
  DECLARE done INT DEFAULT FALSE;
  DECLARE current_tag VARCHAR(255);
  DECLARE alias_address VARCHAR(255);
  DECLARE alias_goto TEXT;

  DECLARE tag_cursor CURSOR FOR
    SELECT DISTINCT tag_name FROM tags_mailbox;

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

  OPEN tag_cursor;

  read_loop: LOOP
    FETCH tag_cursor INTO current_tag;
    IF done THEN
      LEAVE read_loop;
    END IF;

    SET alias_address = CONCAT(current_tag, '_alias@example-mail.org');

    SELECT GROUP_CONCAT(username SEPARATOR ',')
    INTO alias_goto
    FROM tags_mailbox
    WHERE tag_name = current_tag;

    IF EXISTS (
      SELECT 1 FROM alias WHERE address = alias_address
    ) THEN
      UPDATE alias
      SET goto = alias_goto
      WHERE address = alias_address;
    ELSE
      INSERT INTO alias (address, goto, domain)
      VALUES (alias_address, alias_goto, 'example-mail.org');
    END IF;

  END LOOP;

  CLOSE tag_cursor;
END$$

DELIMITER ;
