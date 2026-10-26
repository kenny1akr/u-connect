-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Hôte : 127.0.0.1
-- Généré le : ven. 23 oct. 2026 à 15:39
-- Version du serveur : 10.4.32-MariaDB
-- Version de PHP : 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Base de données : `uconnect_db`
--

DELIMITER $$
--
-- Procédures
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_attach_admission_documents` (IN `p_admission` INT UNSIGNED, IN `p_student` INT UNSIGNED, IN `p_year` INT UNSIGNED)   BEGIN
  UPDATE `enrollment_documents` ed
    JOIN `document_types` dt ON dt.`id`=ed.`document_type_id`
     SET ed.`student_id`=p_student,
         ed.`academic_year_id`=IF(dt.`is_one_time`=0, COALESCE(ed.`academic_year_id`,p_year), ed.`academic_year_id`)
   WHERE ed.`admission_id`=p_admission AND ed.`student_id` IS NULL;
  UPDATE `students` SET `admission_id`=p_admission WHERE `id`=p_student;
  UPDATE `admission_applications` SET `student_id`=p_student, `status`='inscrite' WHERE `id`=p_admission;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_compute_course_result` (IN `p_student` INT UNSIGNED, IN `p_course` INT UNSIGNED, IN `p_year` INT UNSIGNED, IN `p_session` TINYINT UNSIGNED)   BEGIN
  DECLARE v_pass DECIMAL(4,2); DECLARE v_credits TINYINT UNSIGNED;
  DECLARE v_rank TINYINT UNSIGNED; DECLARE v_sem INT UNSIGNED;
  DECLARE v_n INT DEFAULT 0; DECLARE v_avg DECIMAL(5,2); DECLARE v_prev DECIMAL(5,2) DEFAULT NULL;

  SELECT u.`pass_mark`, c.`credits`, u.`semester_rank` INTO v_pass, v_credits, v_rank
    FROM `courses` c LEFT JOIN `teaching_units` u ON u.`id` = c.`unit_id` WHERE c.`id` = p_course;
  SET v_pass = COALESCE(v_pass, 10);

  SELECT s.`id` INTO v_sem FROM `semesters` s
   WHERE s.`academic_year_id` = p_year AND s.`rank_no` = v_rank LIMIT 1;
  IF v_sem IS NULL THEN SELECT `semester_id` INTO v_sem FROM `courses` WHERE `id` = p_course; END IF;
  IF v_sem IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Semestre introuvable pour ce cours et cette année'; END IF;

  IF p_session = 2 THEN
    SELECT `average` INTO v_prev FROM `course_results`
     WHERE `student_id`=p_student AND `course_id`=p_course AND `academic_year_id`=p_year AND `session_no`=1;
  END IF;

  SELECT COUNT(*), ROUND(SUM(COALESCE(g.`score`,0)/e.`max_score`*20*e.`weight`)/SUM(e.`weight`),2)
    INTO v_n, v_avg
    FROM `evaluations` e LEFT JOIN `grades` g ON g.`evaluation_id`=e.`id` AND g.`student_id`=p_student
   WHERE e.`course_id`=p_course AND e.`academic_year_id`=p_year AND e.`is_published`=1
     AND ((p_session=1 AND e.`type`<>'Rattrapage') OR (p_session=2 AND e.`type`<>'Examen'));

  IF v_prev IS NOT NULL AND v_prev >= v_pass THEN SET v_avg = v_prev; SET v_n = 1; END IF;

  IF v_n > 0 AND v_avg IS NOT NULL THEN
    INSERT INTO `course_results`
      (`student_id`,`course_id`,`academic_year_id`,`semester_id`,`session_no`,`average`,`credits_earned`,`status`,`is_compensated`,`validated_at`)
    VALUES (p_student,p_course,p_year,v_sem,p_session,v_avg,
            IF(v_avg>=v_pass,v_credits,0),
            IF(v_avg>=v_pass,'validé',IF(p_session=1,'rattrapage','ajourné')),0,NOW())
    ON DUPLICATE KEY UPDATE
      `average`=VALUES(`average`), `credits_earned`=VALUES(`credits_earned`),
      `status`=VALUES(`status`), `is_compensated`=0, `validated_at`=NOW();
  END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_compute_semester_result` (IN `p_student` INT UNSIGNED, IN `p_year` INT UNSIGNED, IN `p_program` INT UNSIGNED, IN `p_level` VARCHAR(2), IN `p_rank` TINYINT UNSIGNED, IN `p_session` TINYINT UNSIGNED)   BEGIN
  DECLARE v_pass DECIMAL(5,2); DECLARE v_enabled VARCHAR(10);
  DECLARE v_expected INT DEFAULT 0; DECLARE v_n INT DEFAULT 0;
  DECLARE v_total INT DEFAULT 0; DECLARE v_earned INT DEFAULT 0;
  DECLARE v_avg DECIMAL(5,2); DECLARE v_blocking INT DEFAULT 0;
  DECLARE v_comp TINYINT DEFAULT 0; DECLARE v_status VARCHAR(10);

  SELECT CAST(`value` AS DECIMAL(5,2)) INTO v_pass FROM `settings` WHERE `key_name`='pass_mark';
  SET v_pass=COALESCE(v_pass,10);
  SELECT `value` INTO v_enabled FROM `settings` WHERE `key_name`='semester_compensation_enabled';
  SET v_enabled=COALESCE(v_enabled,'1');

  SELECT COUNT(*) INTO v_expected FROM `teaching_units` u
   WHERE u.`program_id`=p_program AND u.`level`=p_level AND u.`semester_rank`=p_rank AND u.`is_active`=1;

  SELECT COUNT(*), COALESCE(SUM(ur.`credits_total`),0), COALESCE(SUM(ur.`credits_earned`),0),
         ROUND(SUM(ur.`average`*ur.`credits_total`)/NULLIF(SUM(ur.`credits_total`),0),2),
         COALESCE(SUM(ur.`status`<>'validé' AND u.`compensable_semester`=0),0)
    INTO v_n, v_total, v_earned, v_avg, v_blocking
    FROM `unit_results` ur JOIN `teaching_units` u ON u.`id`=ur.`unit_id`
   WHERE ur.`student_id`=p_student AND ur.`academic_year_id`=p_year AND ur.`session_no`=p_session
     AND u.`program_id`=p_program AND u.`level`=p_level AND u.`semester_rank`=p_rank AND u.`is_active`=1;

  IF v_n>0 AND v_n=v_expected THEN
    IF v_enabled='1' AND v_avg>=v_pass AND v_blocking=0 AND v_earned<v_total THEN
      UPDATE `unit_results` ur JOIN `teaching_units` u ON u.`id`=ur.`unit_id`
         SET ur.`status`='validé', ur.`credits_earned`=ur.`credits_total`, ur.`compensation_level`='semestre'
       WHERE ur.`student_id`=p_student AND ur.`academic_year_id`=p_year AND ur.`session_no`=p_session
         AND u.`program_id`=p_program AND u.`level`=p_level AND u.`semester_rank`=p_rank AND ur.`status`<>'validé';
      UPDATE `course_results` cr JOIN `courses` c ON c.`id`=cr.`course_id` JOIN `teaching_units` u ON u.`id`=c.`unit_id`
         SET cr.`status`='validé', cr.`credits_earned`=c.`credits`, cr.`is_compensated`=1
       WHERE cr.`student_id`=p_student AND cr.`academic_year_id`=p_year AND cr.`session_no`=p_session
         AND u.`program_id`=p_program AND u.`level`=p_level AND u.`semester_rank`=p_rank AND cr.`status`<>'validé';
      SET v_earned=v_total; SET v_comp=1;
    END IF;
    SET v_status=IF(v_earned>=v_total,'validé',IF(p_session=1,'rattrapage','ajourné'));
    INSERT INTO `semester_results`
      (`student_id`,`academic_year_id`,`semester_rank`,`session_no`,`average`,
       `credits_total`,`credits_earned`,`status`,`is_compensated`)
    VALUES (p_student,p_year,p_rank,p_session,v_avg,v_total,v_earned,v_status,v_comp)
    ON DUPLICATE KEY UPDATE
      `average`=VALUES(`average`), `credits_total`=VALUES(`credits_total`),
      `credits_earned`=VALUES(`credits_earned`), `status`=VALUES(`status`),
      `is_compensated`=VALUES(`is_compensated`);
  END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_compute_unit_result` (IN `p_student` INT UNSIGNED, IN `p_unit` INT UNSIGNED, IN `p_year` INT UNSIGNED, IN `p_session` TINYINT UNSIGNED)   BEGIN
  DECLARE v_pass DECIMAL(4,2); DECLARE v_floor DECIMAL(4,2);
  DECLARE v_comp VARCHAR(10); DECLARE v_cap TINYINT;
  DECLARE v_total INT DEFAULT 0; DECLARE v_ncourses INT DEFAULT 0;
  DECLARE v_nres INT DEFAULT 0; DECLARE v_avg DECIMAL(5,2);
  DECLARE v_failed INT DEFAULT 0; DECLARE v_below INT DEFAULT 0;
  DECLARE v_ok TINYINT DEFAULT 0; DECLARE v_comp_used TINYINT DEFAULT 0;
  DECLARE v_earned INT DEFAULT 0; DECLARE v_status VARCHAR(10);

  SELECT `pass_mark`,`min_course_score`,`compensation`,`capitalize_courses`
    INTO v_pass,v_floor,v_comp,v_cap FROM `teaching_units` WHERE `id`=p_unit;

  SELECT COALESCE(SUM(`credits`),0), COUNT(*) INTO v_total, v_ncourses
    FROM `courses` WHERE `unit_id`=p_unit AND `is_active`=1;

  SELECT COUNT(*), ROUND(SUM(cr.`average`*c.`coefficient`)/SUM(c.`coefficient`),2),
         COALESCE(SUM(cr.`average`<v_pass),0), COALESCE(SUM(cr.`average`<v_floor),0)
    INTO v_nres, v_avg, v_failed, v_below
    FROM `courses` c JOIN `course_results` cr ON cr.`course_id`=c.`id`
     AND cr.`student_id`=p_student AND cr.`academic_year_id`=p_year AND cr.`session_no`=p_session
   WHERE c.`unit_id`=p_unit AND c.`is_active`=1;

  IF v_ncourses>0 AND v_nres=v_ncourses THEN
    IF v_comp='interne' THEN SET v_ok=IF(v_avg>=v_pass AND v_below=0,1,0);
    ELSE SET v_ok=IF(v_failed=0,1,0); END IF;

    IF v_ok=1 THEN
      SET v_status='validé'; SET v_earned=v_total; SET v_comp_used=IF(v_failed>0,1,0);
      UPDATE `course_results` cr JOIN `courses` c ON c.`id`=cr.`course_id`
         SET cr.`status`='validé', cr.`credits_earned`=c.`credits`,
             cr.`is_compensated`=IF(cr.`average`<v_pass,1,0)
       WHERE c.`unit_id`=p_unit AND cr.`student_id`=p_student
         AND cr.`academic_year_id`=p_year AND cr.`session_no`=p_session;
    ELSE
      SET v_status=IF(p_session=1,'rattrapage','ajourné');
      IF v_cap=1 THEN
        SELECT COALESCE(SUM(cr.`credits_earned`),0) INTO v_earned
          FROM `course_results` cr JOIN `courses` c ON c.`id`=cr.`course_id`
         WHERE c.`unit_id`=p_unit AND cr.`student_id`=p_student
           AND cr.`academic_year_id`=p_year AND cr.`session_no`=p_session;
      ELSE
        SET v_earned=0;
        UPDATE `course_results` cr JOIN `courses` c ON c.`id`=cr.`course_id`
           SET cr.`credits_earned`=0, cr.`status`=v_status
         WHERE c.`unit_id`=p_unit AND cr.`student_id`=p_student
           AND cr.`academic_year_id`=p_year AND cr.`session_no`=p_session;
      END IF;
    END IF;

    INSERT INTO `unit_results`
      (`student_id`,`unit_id`,`academic_year_id`,`session_no`,`average`,
       `credits_total`,`credits_earned`,`status`,`compensation_level`)
    VALUES (p_student,p_unit,p_year,p_session,v_avg,v_total,v_earned,v_status,
            IF(v_comp_used=1,'ue','aucune'))
    ON DUPLICATE KEY UPDATE
      `average`=VALUES(`average`), `credits_total`=VALUES(`credits_total`),
      `credits_earned`=VALUES(`credits_earned`), `status`=VALUES(`status`),
      `compensation_level`=VALUES(`compensation_level`);
  END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_compute_year_result` (IN `p_student` INT UNSIGNED, IN `p_year` INT UNSIGNED, IN `p_session` TINYINT UNSIGNED)   BEGIN
  DECLARE v_program INT UNSIGNED; DECLARE v_level VARCHAR(2);
  DECLARE v_i INT DEFAULT 0; DECLARE v_n INT DEFAULT 0; DECLARE v_id INT UNSIGNED;
  DECLARE v_req INT DEFAULT 0; DECLARE v_earned INT DEFAULT 0; DECLARE v_avg DECIMAL(5,2);
  DECLARE v_min_adv INT; DECLARE v_decision VARCHAR(20); DECLARE v_mention VARCHAR(80) DEFAULT NULL;

  SELECT `program_id`,`level` INTO v_program, v_level FROM `enrollments`
   WHERE `student_id`=p_student AND `academic_year_id`=p_year AND `status`='validée'
   ORDER BY `id` DESC LIMIT 1;
  IF v_program IS NULL THEN
    SELECT `program_id`,`current_level` INTO v_program, v_level FROM `students` WHERE `id`=p_student;
  END IF;
  IF v_program IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Programme introuvable pour cet étudiant'; END IF;

  SELECT CAST(`value` AS SIGNED) INTO v_min_adv FROM `settings` WHERE `key_name`='min_credits_to_advance';
  SET v_min_adv=COALESCE(v_min_adv,45);

  SELECT COUNT(*) INTO v_n FROM `courses` c JOIN `teaching_units` u ON u.`id`=c.`unit_id`
   WHERE u.`program_id`=v_program AND u.`level`=v_level AND u.`is_active`=1 AND c.`is_active`=1;
  SET v_i=0;
  WHILE v_i<v_n DO
    SELECT c.`id` INTO v_id FROM `courses` c JOIN `teaching_units` u ON u.`id`=c.`unit_id`
     WHERE u.`program_id`=v_program AND u.`level`=v_level AND u.`is_active`=1 AND c.`is_active`=1
     ORDER BY c.`id` LIMIT v_i,1;
    CALL sp_compute_course_result(p_student,v_id,p_year,p_session);
    SET v_i=v_i+1;
  END WHILE;

  SELECT COUNT(*) INTO v_n FROM `teaching_units` u
   WHERE u.`program_id`=v_program AND u.`level`=v_level AND u.`is_active`=1;
  SET v_i=0;
  WHILE v_i<v_n DO
    SELECT u.`id` INTO v_id FROM `teaching_units` u
     WHERE u.`program_id`=v_program AND u.`level`=v_level AND u.`is_active`=1
     ORDER BY u.`id` LIMIT v_i,1;
    CALL sp_compute_unit_result(p_student,v_id,p_year,p_session);
    SET v_i=v_i+1;
  END WHILE;

  CALL sp_compute_semester_result(p_student,p_year,v_program,v_level,1,p_session);
  CALL sp_compute_semester_result(p_student,p_year,v_program,v_level,2,p_session);

  SELECT COALESCE(SUM(sr.`credits_total`),0), COALESCE(SUM(sr.`credits_earned`),0),
         ROUND(SUM(sr.`average`*sr.`credits_total`)/NULLIF(SUM(sr.`credits_total`),0),2)
    INTO v_req, v_earned, v_avg
    FROM `semester_results` sr
   WHERE sr.`student_id`=p_student AND sr.`academic_year_id`=p_year AND sr.`session_no`=p_session;

  IF v_req>0 THEN
    IF v_earned>=v_req THEN SET v_decision='admis';
    ELSEIF p_session=1 THEN SET v_decision='rattrapage';
    ELSEIF v_earned>=v_min_adv THEN SET v_decision='admis_avec_dettes';
    ELSE SET v_decision='ajourné'; END IF;

    IF v_decision='admis' AND v_avg IS NOT NULL THEN
      SELECT `label` INTO v_mention FROM `grade_mentions`
       WHERE `is_pass`=1 AND v_avg>=`min_score` ORDER BY `min_score` DESC LIMIT 1;
    END IF;

    INSERT INTO `year_results`
      (`student_id`,`academic_year_id`,`program_id`,`level`,`session_no`,`average`,
       `credits_required`,`credits_earned`,`decision`,`mention_label`)
    VALUES (p_student,p_year,v_program,v_level,p_session,v_avg,v_req,v_earned,v_decision,v_mention)
    ON DUPLICATE KEY UPDATE
      `program_id`=VALUES(`program_id`), `level`=VALUES(`level`), `average`=VALUES(`average`),
      `credits_required`=VALUES(`credits_required`), `credits_earned`=VALUES(`credits_earned`),
      `decision`=VALUES(`decision`), `mention_label`=VALUES(`mention_label`);
  END IF;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_generate_copies` (IN `p_book` INT UNSIGNED)   BEGIN
  DECLARE v_total INT DEFAULT 0; DECLARE v_have INT DEFAULT 0;
  DECLARE v_avail INT DEFAULT 0; DECLARE v_n INT;
  SELECT `total_copies`,`available_copies` INTO v_total,v_avail FROM `books` WHERE `id`=p_book;
  SELECT COUNT(*) INTO v_have FROM `book_copies` WHERE `book_id`=p_book;
  SET v_n=v_have+1;
  WHILE v_n<=v_total DO
    INSERT INTO `book_copies` (`book_id`,`barcode`,`status`,`acquired_at`)
    VALUES (p_book, CONCAT('B',LPAD(p_book,5,'0'),'-',LPAD(v_n,3,'0')),
            IF(v_n<=v_avail+v_have,'disponible','emprunté'), CURDATE());
    SET v_n=v_n+1;
  END WHILE;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_generate_payslip` (IN `p_period` INT UNSIGNED, IN `p_user` INT UNSIGNED)   BEGIN
  DECLARE v_done INT DEFAULT 0; DECLARE v_month DATE; DECLARE v_last DATE;
  DECLARE v_contract INT UNSIGNED; DECLARE v_base DECIMAL(12,2) DEFAULT 0;
  DECLARE v_cur CHAR(3) DEFAULT 'BIF'; DECLARE v_hours DECIMAL(7,2) DEFAULT 0;
  DECLARE v_rate DECIMAL(12,2) DEFAULT 0; DECLARE v_vac DECIMAL(12,2) DEFAULT 0;
  DECLARE v_cat VARCHAR(20) DEFAULT 'tous'; DECLARE v_ps BIGINT UNSIGNED; DECLARE v_pst VARCHAR(20);
  DECLARE v_gross DECIMAL(12,2) DEFAULT 0; DECLARE v_ded DECIMAL(12,2) DEFAULT 0;
  DECLARE v_amt DECIMAL(12,2); DECLARE v_assiette DECIMAL(12,2);
  DECLARE r_id INT UNSIGNED; DECLARE r_label VARCHAR(150); DECLARE r_kind VARCHAR(10);
  DECLARE r_calc VARCHAR(15); DECLARE r_value DECIMAL(12,4); DECLARE r_base VARCHAR(10);
  DECLARE c_rule CURSOR FOR
    SELECT `id`,`label`,`kind`,`calc`,`value`,`base` FROM `payroll_rules`
     WHERE `is_active`=1 AND (`applies_to`='tous' OR `applies_to`=v_cat) ORDER BY (`kind`='retenue'),`id`;
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done=1;

  SELECT `period_month` INTO v_month FROM `payroll_periods` WHERE `id`=p_period;
  IF v_month IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Période de paie introuvable'; END IF;
  SET v_last=LAST_DAY(v_month);

  SELECT `id`,`base_salary`,`currency` INTO v_contract,v_base,v_cur FROM `staff_contracts`
   WHERE `user_id`=p_user AND `status`='actif'
     AND `start_date`<=v_last AND (`end_date` IS NULL OR `end_date`>=v_month)
   ORDER BY `start_date` DESC LIMIT 1;
  SET v_base=COALESCE(v_base,0);

  SELECT COALESCE(`staff_category`,'tous') INTO v_cat FROM `staff_profiles` WHERE `user_id`=p_user;
  SET v_cat=COALESCE(v_cat,'tous');

  SELECT COALESCE(SUM(`hours`),0) INTO v_hours FROM `class_sessions`
   WHERE `teacher_id`=p_user AND `status`='tenue' AND `payroll_status`='validée'
     AND `session_date` BETWEEN v_month AND v_last;
  SELECT COALESCE(`hourly_rate`,0) INTO v_rate FROM `teacher_profiles` WHERE `user_id`=p_user;
  SET v_rate=COALESCE(v_rate,0);
  SET v_vac=ROUND(v_hours*v_rate,2);

  SELECT `id`,`status` INTO v_ps,v_pst FROM `payslips` WHERE `period_id`=p_period AND `user_id`=p_user;
  IF v_ps IS NOT NULL THEN
    IF v_pst<>'brouillon' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Fiche déjà validée ou payée : recalcul interdit'; END IF;
    DELETE FROM `payslip_items` WHERE `payslip_id`=v_ps;
  ELSE
    INSERT INTO `payslips` (`period_id`,`user_id`,`contract_id`,`currency`) VALUES (p_period,p_user,v_contract,v_cur);
    SET v_ps=LAST_INSERT_ID();
  END IF;

  IF v_base>0 THEN
    INSERT INTO `payslip_items` (`payslip_id`,`kind`,`label`,`amount`) VALUES (v_ps,'gain','Salaire de base',v_base);
  END IF;
  IF v_vac>0 THEN
    INSERT INTO `payslip_items` (`payslip_id`,`kind`,`label`,`amount`)
    VALUES (v_ps,'gain',CONCAT('Vacations (',v_hours,' h)'),v_vac);
  END IF;
  SET v_gross=v_base+v_vac;

  OPEN c_rule;
  rule_loop: LOOP
    FETCH c_rule INTO r_id,r_label,r_kind,r_calc,r_value,r_base;
    IF v_done=1 THEN LEAVE rule_loop; END IF;
    SET v_assiette=IF(r_base='brut',v_gross,v_base);
    IF r_calc='pourcentage' THEN SET v_amt=ROUND(v_assiette*r_value/100,2);
    ELSEIF r_calc='fixe' THEN SET v_amt=r_value;
    ELSE
      SELECT COALESCE(ROUND(SUM(GREATEST(0, LEAST(v_assiette, COALESCE(`to_amount`,v_assiette))-`from_amount`)*`rate`/100),2),0)
        INTO v_amt FROM `payroll_tax_brackets` WHERE `rule_id`=r_id;
    END IF;
    IF v_amt>0 THEN
      INSERT INTO `payslip_items` (`payslip_id`,`rule_id`,`kind`,`label`,`amount`)
      VALUES (v_ps,r_id,r_kind,r_label,v_amt);
      IF r_kind='gain' THEN SET v_gross=v_gross+v_amt; ELSE SET v_ded=v_ded+v_amt; END IF;
    END IF;
  END LOOP;
  CLOSE c_rule;

  UPDATE `payslips`
     SET `contract_id`=v_contract, `base_salary`=v_base, `vacation_hours`=v_hours,
         `vacation_amount`=v_vac, `total_gains`=v_gross, `total_deductions`=v_ded,
         `net_pay`=v_gross-v_ded, `currency`=v_cur
   WHERE `id`=v_ps;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_generate_period_payslips` (IN `p_period` INT UNSIGNED)   BEGIN
  DECLARE v_done INT DEFAULT 0; DECLARE v_user INT UNSIGNED;
  DECLARE c_staff CURSOR FOR SELECT `user_id` FROM `staff_profiles` WHERE `employment_status` IN ('actif','en_congé');
  DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done=1;
  OPEN c_staff;
  staff_loop: LOOP
    FETCH c_staff INTO v_user;
    IF v_done=1 THEN LEAVE staff_loop; END IF;
    IF NOT EXISTS (SELECT 1 FROM `payslips` WHERE `period_id`=p_period AND `user_id`=v_user AND `status`<>'brouillon') THEN
      CALL sp_generate_payslip(p_period,v_user);
    END IF;
  END LOOP;
  CLOSE c_staff;
  UPDATE `payroll_periods` SET `status`='calculée' WHERE `id`=p_period AND `status`='ouverte';
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_next_matricule` (IN `p_campus` INT UNSIGNED, OUT `p_matricule` VARCHAR(30))   BEGIN
  DECLARE v_code VARCHAR(20); DECLARE v_yy CHAR(2); DECLARE v_key VARCHAR(50);
  SELECT `code` INTO v_code FROM `campuses` WHERE `id`=p_campus;
  IF v_code IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Campus introuvable'; END IF;
  SELECT RIGHT(YEAR(`start_date`),2) INTO v_yy FROM `academic_years` WHERE `is_current`=1 LIMIT 1;
  SET v_yy=COALESCE(v_yy,DATE_FORMAT(CURDATE(),'%y'));
  SET v_key=CONCAT('matricule:',v_code,':',v_yy);
  INSERT INTO `sequences` (`name`,`current_value`) VALUES (v_key,LAST_INSERT_ID(1))
  ON DUPLICATE KEY UPDATE `current_value`=LAST_INSERT_ID(`current_value`+1);
  SET p_matricule=CONCAT('UIA-',v_code,'-',v_yy,'-',LPAD(LAST_INSERT_ID(),4,'0'));
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `sp_renew_loan` (IN `p_loan` BIGINT UNSIGNED)   BEGIN
  DECLARE v_book INT UNSIGNED; DECLARE v_student INT UNSIGNED; DECLARE v_user INT UNSIGNED;
  DECLARE v_ret DATETIME; DECLARE v_renew TINYINT UNSIGNED; DECLARE v_type VARCHAR(20);
  DECLARE v_days SMALLINT UNSIGNED; DECLARE v_maxr TINYINT UNSIGNED; DECLARE v_unpaid DECIMAL(12,2) DEFAULT 0;

  SELECT `book_id`,`student_id`,`user_id`,`returned_at`,`renewals`
    INTO v_book,v_student,v_user,v_ret,v_renew FROM `book_loans` WHERE `id`=p_loan;
  IF v_book IS NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Prêt introuvable'; END IF;
  IF v_ret IS NOT NULL THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Ce livre est déjà retourné'; END IF;

  SET v_type=fn_borrower_type(v_student,v_user);
  SELECT `loan_days`,`max_renewals` INTO v_days,v_maxr FROM `loan_policies` WHERE `borrower_type`=v_type;
  IF v_maxr IS NULL OR v_renew>=v_maxr THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Nombre maximal de renouvellements atteint';
  END IF;
  IF EXISTS (SELECT 1 FROM `book_reservations` WHERE `book_id`=v_book AND `status` IN ('en_attente','disponible')) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Renouvellement impossible : le livre est réservé par un autre lecteur';
  END IF;
  SELECT COALESCE(SUM(`amount`),0) INTO v_unpaid FROM `library_fines`
   WHERE `status`='impayée'
     AND ((v_student IS NOT NULL AND `student_id`=v_student) OR (v_student IS NULL AND `user_id`=v_user));
  IF v_unpaid>0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Renouvellement refusé : amendes impayées'; END IF;

  UPDATE `book_loans`
     SET `due_date`=GREATEST(`due_date`,CURDATE())+INTERVAL v_days DAY,
         `renewals`=`renewals`+1, `status`='en_cours'
   WHERE `id`=p_loan;
END$$

--
-- Fonctions
--
CREATE DEFINER=`root`@`localhost` FUNCTION `fn_borrower_type` (`p_student` INT UNSIGNED, `p_user` INT UNSIGNED) RETURNS VARCHAR(20) CHARSET utf8mb4 COLLATE utf8mb4_general_ci READS SQL DATA BEGIN
  DECLARE v_slug VARCHAR(50);
  IF p_student IS NOT NULL THEN RETURN 'etudiant'; END IF;
  SELECT r.`slug` INTO v_slug FROM `users` u LEFT JOIN `roles` r ON r.`id` = u.`role_id` WHERE u.`id` = p_user;
  RETURN IF(v_slug = 'enseignant', 'enseignant', 'personnel');
END$$

CREATE DEFINER=`root`@`localhost` FUNCTION `fn_missing_docs_count` (`p_student` INT UNSIGNED, `p_program` INT UNSIGNED, `p_year` INT UNSIGNED, `p_level` VARCHAR(2), `p_etype` VARCHAR(20)) RETURNS INT(11) READS SQL DATA BEGIN
  DECLARE v_inst VARCHAR(20);
  DECLARE v_nat VARCHAR(80);
  DECLARE v_cycle VARCHAR(10);
  DECLARE v_n INT DEFAULT 0;

  SELECT f.`institution_type` INTO v_inst
    FROM `programs` p
    JOIN `departments` dp ON dp.`id` = p.`department_id`
    JOIN `faculties` f ON f.`id` = dp.`faculty_id`
   WHERE p.`id` = p_program;
  SELECT COALESCE(`nationality`,'Burundaise') INTO v_nat FROM `students` WHERE `id` = p_student;
  SET v_cycle = CASE WHEN p_level IN ('L1','L2','L3') THEN 'licence'
                     WHEN p_level IN ('M1','M2') THEN 'master' ELSE 'doctorat' END;

  SELECT COUNT(*) INTO v_n FROM (
    SELECT COALESCE(r.`alt_group`, CONCAT('R', r.`id`)) AS k,
           SUM(EXISTS (SELECT 1 FROM `enrollment_documents` d
                        WHERE d.`student_id` = p_student
                          AND d.`document_type_id` = r.`document_type_id`
                          AND d.`status` IN ('reçu','validé')
                          AND d.`quantity` >= r.`min_quantity`
                          AND (dt.`is_one_time` = 1 OR d.`academic_year_id` = p_year))) AS ok
      FROM `document_requirements` r
      JOIN `document_types` dt ON dt.`id` = r.`document_type_id`
     WHERE r.`is_active` = 1 AND r.`is_mandatory` = 1
       AND (r.`institution_type` IS NULL OR r.`institution_type` = v_inst)
       AND (r.`cycle` IS NULL OR r.`cycle` = v_cycle)
       AND (r.`enrollment_type` IS NULL OR r.`enrollment_type` = p_etype)
       AND (r.`foreign_only` = 0 OR v_nat NOT LIKE 'Burund%')
     GROUP BY k
    HAVING ok = 0) x;
  RETURN v_n;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Structure de la table `academic_calendar`
--

CREATE TABLE `academic_calendar` (
  `id` int(10) UNSIGNED NOT NULL,
  `academic_year_id` int(10) UNSIGNED NOT NULL,
  `campus_id` int(10) UNSIGNED DEFAULT NULL,
  `type` enum('inscription','réinscription','début_cours','examens','rattrapage','délibération','proclamation','vacances','jour_férié','autre') NOT NULL,
  `title` varchar(200) NOT NULL,
  `start_date` date NOT NULL,
  `end_date` date NOT NULL,
  `description` text DEFAULT NULL,
  `created_by` int(10) UNSIGNED DEFAULT NULL
) ;

-- --------------------------------------------------------

--
-- Structure de la table `academic_years`
--

CREATE TABLE `academic_years` (
  `id` int(10) UNSIGNED NOT NULL,
  `label` varchar(20) NOT NULL,
  `start_date` date NOT NULL,
  `end_date` date NOT NULL,
  `is_current` tinyint(1) NOT NULL DEFAULT 0,
  `is_closed` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `current_flag` tinyint(4) GENERATED ALWAYS AS (if(`is_current` = 1,1,NULL)) STORED
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Déchargement des données de la table `academic_years`
--

INSERT INTO `academic_years` (`id`, `label`, `start_date`, `end_date`, `is_current`, `is_closed`, `created_at`) VALUES
(1, '2026-2027', '2026-09-01', '2027-06-30', 1, 0, '2026-10-20 16:28:27');

-- --------------------------------------------------------

--
-- Structure de la table `activity_logs`
--

CREATE TABLE `activity_logs` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `user_id` int(10) UNSIGNED DEFAULT NULL,
  `action` varchar(100) NOT NULL,
  `entity` varchar(100) DEFAULT NULL,
  `entity_id` bigint(20) UNSIGNED DEFAULT NULL,
  `payload` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`payload`)),
  `ip_address` varchar(45) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `admin_activity_logs`
--

CREATE TABLE `admin_activity_logs` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `admin_user_id` int(10) UNSIGNED NOT NULL,
  `action` varchar(100) NOT NULL,
  `entity` varchar(100) DEFAULT NULL,
  `entity_id` bigint(20) UNSIGNED DEFAULT NULL,
  `payload` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`payload`)),
  `ip_address` varchar(45) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `admin_users`
--

CREATE TABLE `admin_users` (
  `id` int(10) UNSIGNED NOT NULL,
  `uuid` char(36) NOT NULL,
  `user_name` varchar(100) NOT NULL,
  `email` varchar(150) NOT NULL,
  `phone` varchar(30) DEFAULT NULL,
  `password_hash` varchar(255) NOT NULL,
  `f_name` varchar(100) NOT NULL,
  `l_name` varchar(100) NOT NULL,
  `gender` enum('M','F','O') DEFAULT 'O',
  `birth_date` date DEFAULT NULL,
  `admin_role` enum('admin','super_admin') NOT NULL DEFAULT 'admin',
  `campus_id` int(10) UNSIGNED DEFAULT NULL,
  `status` enum('actif','désactivé','suspendu') NOT NULL DEFAULT 'actif',
  `profil` varchar(255) DEFAULT NULL,
  `must_change_password` tinyint(1) NOT NULL DEFAULT 0,
  `failed_attempts` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `locked_until` datetime DEFAULT NULL,
  `password_changed_at` datetime DEFAULT NULL,
  `email_verified_at` datetime DEFAULT NULL,
  `last_login_at` datetime DEFAULT NULL,
  `shadow_user_id` int(10) UNSIGNED DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Déchargement des données de la table `admin_users`
--

INSERT INTO `admin_users` (`id`, `uuid`, `user_name`, `email`, `phone`, `password_hash`, `f_name`, `l_name`, `gender`, `birth_date`, `admin_role`, `campus_id`, `status`, `profil`, `must_change_password`, `failed_attempts`, `locked_until`, `password_changed_at`, `email_verified_at`, `last_login_at`, `shadow_user_id`, `created_at`, `updated_at`) VALUES
(1, 'a493ccbc-cc92-11f1-bdf4-4c327596066b', 'superadmin', 'superadmin@uia.edu.bi', '+257 79 000 000', '$2y$10$e0MYzXyjpJS7Pd0RVvHwHe1K7l0w7Z0h1f8D9oQ8vB1wZ9kQmQ9eO', 'Super', 'Administrateur', 'M', NULL, 'super_admin', NULL, 'actif', NULL, 1, 0, NULL, NULL, NULL, NULL, 1, '2026-10-20 16:29:22', '2026-10-23 13:34:35');

--
-- Déclencheurs `admin_users`
--
DELIMITER $$
CREATE TRIGGER `trg_admin_users_bi` BEFORE INSERT ON `admin_users` FOR EACH ROW BEGIN
  DECLARE v_role_id INT UNSIGNED; DECLARE v_shadow_id INT UNSIGNED;
  IF NEW.`admin_role` NOT IN ('admin','super_admin') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='admin_users.admin_role : seules valeurs admin ou super_admin';
  END IF;
  IF NEW.`shadow_user_id` IS NULL THEN
    SELECT `id` INTO v_role_id FROM `roles` WHERE `slug`='system_admin' LIMIT 1;
    IF v_role_id IS NULL THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Rôle technique system_admin introuvable';
    END IF;
    INSERT INTO `users`
      (`uuid`,`user_name`,`email`,`phone`,`password_hash`,`f_name`,`l_name`,
       `gender`,`birth_date`,`category`,`role_id`,`campus_id`,`status`,`profil`,
       `must_change_password`,`email_verified_at`,`last_login_at`)
    VALUES
      (NEW.`uuid`,NEW.`user_name`,NEW.`email`,NEW.`phone`,NEW.`password_hash`,
       NEW.`f_name`,NEW.`l_name`,NEW.`gender`,NEW.`birth_date`,
       'system_admin',v_role_id,NEW.`campus_id`,NEW.`status`,NEW.`profil`,
       NEW.`must_change_password`,NEW.`email_verified_at`,NEW.`last_login_at`);
    SET v_shadow_id=LAST_INSERT_ID();
    SET NEW.`shadow_user_id`=v_shadow_id;
  END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_admin_users_bu` BEFORE UPDATE ON `admin_users` FOR EACH ROW BEGIN
  IF NEW.`admin_role` NOT IN ('admin','super_admin') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='admin_users.admin_role : seules valeurs admin ou super_admin';
  END IF;
  IF NOT (NEW.`password_hash` <=> OLD.`password_hash`) THEN
    SET NEW.`password_changed_at` = NOW();
    SET NEW.`must_change_password` = 0;
  END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Structure de la table `admission_applications`
--

CREATE TABLE `admission_applications` (
  `id` int(10) UNSIGNED NOT NULL,
  `reference` varchar(30) NOT NULL,
  `first_name` varchar(100) NOT NULL,
  `last_name` varchar(100) NOT NULL,
  `gender` enum('M','F','O') NOT NULL DEFAULT 'O',
  `birth_date` date DEFAULT NULL,
  `birth_place` varchar(150) DEFAULT NULL,
  `nationality` varchar(80) NOT NULL DEFAULT 'Burundaise',
  `national_id` varchar(30) DEFAULT NULL,
  `phone` varchar(30) DEFAULT NULL,
  `email` varchar(150) DEFAULT NULL,
  `province_origin` varchar(100) DEFAULT NULL,
  `commune_origin` varchar(100) DEFAULT NULL,
  `campus_id` int(10) UNSIGNED NOT NULL,
  `program_id` int(10) UNSIGNED NOT NULL,
  `level` enum('L1','L2','L3','M1','M2','D') NOT NULL DEFAULT 'L1',
  `secondary_school` varchar(150) DEFAULT NULL,
  `secondary_section` varchar(100) DEFAULT NULL,
  `secondary_diploma_year` smallint(5) UNSIGNED DEFAULT NULL,
  `secondary_diploma_percentage` decimal(5,2) DEFAULT NULL,
  `entrance_exam_score` decimal(5,2) DEFAULT NULL,
  `status` enum('soumise','en_examen','admise','liste_attente','refusée','inscrite') NOT NULL DEFAULT 'soumise',
  `student_id` int(10) UNSIGNED DEFAULT NULL,
  `reviewed_by` int(10) UNSIGNED DEFAULT NULL,
  `reviewed_at` datetime DEFAULT NULL,
  `notes` text DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ;

-- --------------------------------------------------------

--
-- Structure de la table `alerts`
--

CREATE TABLE `alerts` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `type` varchar(50) NOT NULL,
  `priority` enum('basse','moyenne','haute','critique') NOT NULL DEFAULT 'moyenne',
  `title` varchar(200) NOT NULL,
  `message` text DEFAULT NULL,
  `target_user_id` int(10) UNSIGNED DEFAULT NULL,
  `target_role` varchar(50) DEFAULT NULL,
  `campus_id` int(10) UNSIGNED DEFAULT NULL,
  `is_dismissed` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `announcements`
--

CREATE TABLE `announcements` (
  `id` int(10) UNSIGNED NOT NULL,
  `title` varchar(200) NOT NULL,
  `content` text NOT NULL,
  `target_role` varchar(50) DEFAULT NULL,
  `campus_id` int(10) UNSIGNED DEFAULT NULL,
  `program_id` int(10) UNSIGNED DEFAULT NULL,
  `published_at` datetime NOT NULL DEFAULT current_timestamp(),
  `expires_at` datetime DEFAULT NULL,
  `created_by` int(10) UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `attendance`
--

CREATE TABLE `attendance` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `class_session_id` bigint(20) UNSIGNED NOT NULL,
  `student_id` int(10) UNSIGNED NOT NULL,
  `status` enum('présent','absent','retard','excusé') NOT NULL DEFAULT 'présent',
  `justification` varchar(255) DEFAULT NULL,
  `recorded_by` int(10) UNSIGNED DEFAULT NULL,
  `recorded_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `books`
--

CREATE TABLE `books` (
  `id` int(10) UNSIGNED NOT NULL,
  `isbn` varchar(20) DEFAULT NULL,
  `title` varchar(255) NOT NULL,
  `book_type` enum('livre','manuel','mémoire','thèse','revue','rapport','numérique') NOT NULL DEFAULT 'livre',
  `author` varchar(200) DEFAULT NULL,
  `editor` varchar(150) DEFAULT NULL,
  `year_published` smallint(5) UNSIGNED DEFAULT NULL,
  `language` varchar(30) DEFAULT 'Français',
  `pages` smallint(5) UNSIGNED DEFAULT NULL,
  `category` varchar(100) DEFAULT NULL,
  `shelf_location` varchar(50) DEFAULT NULL COMMENT 'Rayon / cote de rangement',
  `department_id` int(10) UNSIGNED DEFAULT NULL,
  `description` text DEFAULT NULL,
  `ebook_path` varchar(255) DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `total_copies` smallint(5) UNSIGNED NOT NULL DEFAULT 1,
  `available_copies` smallint(5) UNSIGNED NOT NULL DEFAULT 1,
  `campus_id` int(10) UNSIGNED DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ;

--
-- Déclencheurs `books`
--
DELIMITER $$
CREATE TRIGGER `trg_books_ai_copies` AFTER INSERT ON `books` FOR EACH ROW BEGIN
  IF NEW.`total_copies`>0 THEN CALL sp_generate_copies(NEW.`id`); END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Structure de la table `book_acquisitions`
--

CREATE TABLE `book_acquisitions` (
  `id` int(10) UNSIGNED NOT NULL,
  `book_id` int(10) UNSIGNED NOT NULL,
  `acquisition_type` enum('achat','don','dépôt_mémoire') NOT NULL DEFAULT 'achat',
  `quantity` smallint(5) UNSIGNED NOT NULL DEFAULT 1,
  `unit_price` decimal(12,2) NOT NULL DEFAULT 0.00,
  `currency` char(3) NOT NULL DEFAULT 'BIF',
  `supplier` varchar(150) DEFAULT NULL,
  `acquired_at` date NOT NULL DEFAULT curdate(),
  `received_by` int(10) UNSIGNED DEFAULT NULL,
  `notes` varchar(255) DEFAULT NULL
) ;

-- --------------------------------------------------------

--
-- Structure de la table `book_copies`
--

CREATE TABLE `book_copies` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `book_id` int(10) UNSIGNED NOT NULL,
  `barcode` varchar(40) NOT NULL,
  `condition_state` enum('neuf','bon','usé','endommagé') NOT NULL DEFAULT 'bon',
  `status` enum('disponible','emprunté','perdu','endommagé','retiré') NOT NULL DEFAULT 'disponible',
  `acquired_at` date DEFAULT NULL,
  `notes` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `book_loans`
--

CREATE TABLE `book_loans` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `book_id` int(10) UNSIGNED NOT NULL,
  `copy_id` bigint(20) UNSIGNED DEFAULT NULL,
  `student_id` int(10) UNSIGNED DEFAULT NULL,
  `user_id` int(10) UNSIGNED DEFAULT NULL,
  `loan_date` date NOT NULL DEFAULT curdate(),
  `due_date` date NOT NULL,
  `renewals` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `returned_at` datetime DEFAULT NULL,
  `status` enum('en_cours','retourné','retard') NOT NULL DEFAULT 'en_cours',
  `issued_by` int(10) UNSIGNED NOT NULL
) ;

--
-- Déclencheurs `book_loans`
--
DELIMITER $$
CREATE TRIGGER `trg_book_loans_ai` AFTER INSERT ON `book_loans` FOR EACH ROW BEGIN
  IF NEW.`returned_at` IS NULL THEN
    UPDATE `books` SET `available_copies`=`available_copies`-1 WHERE `id`=NEW.`book_id`;
    IF NEW.`copy_id` IS NOT NULL THEN
      UPDATE `book_copies` SET `status`='emprunté' WHERE `id`=NEW.`copy_id`;
    END IF;
    UPDATE `book_reservations` SET `status`='honorée'
     WHERE `book_id`=NEW.`book_id` AND `status` IN ('en_attente','disponible')
       AND ((NEW.`student_id` IS NOT NULL AND `student_id`=NEW.`student_id`)
         OR (NEW.`student_id` IS NULL AND `user_id`=NEW.`user_id`));
  END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_book_loans_au` AFTER UPDATE ON `book_loans` FOR EACH ROW BEGIN
  DECLARE v_rate DECIMAL(10,2) DEFAULT 0; DECLARE v_cur CHAR(3) DEFAULT 'BIF';
  DECLARE v_days INT DEFAULT 0; DECLARE v_res BIGINT UNSIGNED;
  DECLARE v_rs INT UNSIGNED; DECLARE v_ru INT UNSIGNED; DECLARE v_uid INT UNSIGNED;
  IF OLD.`returned_at` IS NULL AND NEW.`returned_at` IS NOT NULL THEN
    UPDATE `books` SET `available_copies`=`available_copies`+1 WHERE `id`=NEW.`book_id`;
    IF NEW.`copy_id` IS NOT NULL THEN
      UPDATE `book_copies` SET `status`='disponible' WHERE `id`=NEW.`copy_id` AND `status`='emprunté';
    END IF;
    SET v_days=DATEDIFF(DATE(NEW.`returned_at`),NEW.`due_date`);
    IF v_days>0 THEN
      SELECT `fine_per_day`,`currency` INTO v_rate,v_cur FROM `loan_policies`
       WHERE `borrower_type`=fn_borrower_type(NEW.`student_id`,NEW.`user_id`);
      IF v_rate>0 THEN
        INSERT INTO `library_fines` (`loan_id`,`student_id`,`user_id`,`days_late`,`amount`,`currency`,`reason`)
        VALUES (NEW.`id`,NEW.`student_id`,NEW.`user_id`,v_days,v_days*v_rate,v_cur,'retard');
      END IF;
    END IF;
    SELECT `id`,`student_id`,`user_id` INTO v_res,v_rs,v_ru FROM `book_reservations`
     WHERE `book_id`=NEW.`book_id` AND `status`='en_attente'
     ORDER BY `reserved_at` LIMIT 1;
    IF v_res IS NOT NULL THEN
      UPDATE `book_reservations`
         SET `status`='disponible', `notified_at`=NOW(), `expires_at`=NOW()+INTERVAL 3 DAY
       WHERE `id`=v_res;
      SET v_uid=COALESCE(v_ru,(SELECT `user_id` FROM `students` WHERE `id`=v_rs));
      IF v_uid IS NOT NULL THEN
        INSERT INTO `notifications` (`user_id`,`type`,`title`,`body`)
        VALUES (v_uid,'bibliotheque','Livre disponible',
                'Le livre que vous avez réservé est disponible. Il vous est réservé pendant 3 jours.');
      END IF;
    END IF;
  END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_book_loans_bi` BEFORE INSERT ON `book_loans` FOR EACH ROW BEGIN
  DECLARE v_type VARCHAR(20); DECLARE v_max TINYINT UNSIGNED; DECLARE v_block TINYINT;
  DECLARE v_cnt INT DEFAULT 0; DECLARE v_unpaid DECIMAL(12,2) DEFAULT 0;
  DECLARE v_cstatus VARCHAR(20);
  IF NEW.`returned_at` IS NULL THEN
    IF (SELECT `available_copies` FROM `books` WHERE `id`=NEW.`book_id`)<1 THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Aucun exemplaire disponible pour ce livre';
    END IF;
    SET v_type=fn_borrower_type(NEW.`student_id`,NEW.`user_id`);
    SELECT `max_loans`,`block_if_unpaid_fines` INTO v_max,v_block
      FROM `loan_policies` WHERE `borrower_type`=v_type;
    IF v_max IS NOT NULL THEN
      SELECT COUNT(*) INTO v_cnt FROM `book_loans` WHERE `returned_at` IS NULL
        AND ((NEW.`student_id` IS NOT NULL AND `student_id`=NEW.`student_id`)
          OR (NEW.`student_id` IS NULL AND `user_id`=NEW.`user_id`));
      IF v_cnt>=v_max THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Limite de prêts simultanés atteinte'; END IF;
      IF v_block=1 THEN
        SELECT COALESCE(SUM(`amount`),0) INTO v_unpaid FROM `library_fines`
         WHERE `status`='impayée'
           AND ((NEW.`student_id` IS NOT NULL AND `student_id`=NEW.`student_id`)
             OR (NEW.`student_id` IS NULL AND `user_id`=NEW.`user_id`));
        IF v_unpaid>0 THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Prêt refusé : amendes impayées'; END IF;
      END IF;
    END IF;
    IF NEW.`copy_id` IS NOT NULL THEN
      SELECT `status` INTO v_cstatus FROM `book_copies` WHERE `id`=NEW.`copy_id` AND `book_id`=NEW.`book_id`;
      IF v_cstatus IS NULL OR v_cstatus<>'disponible' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Cet exemplaire n''est pas disponible';
      END IF;
    END IF;
  END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_book_loans_bu` BEFORE UPDATE ON `book_loans` FOR EACH ROW BEGIN
  IF NEW.`returned_at` IS NOT NULL THEN SET NEW.`status`='retourné'; END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Structure de la table `book_reservations`
--

CREATE TABLE `book_reservations` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `book_id` int(10) UNSIGNED NOT NULL,
  `student_id` int(10) UNSIGNED DEFAULT NULL,
  `user_id` int(10) UNSIGNED DEFAULT NULL,
  `reserved_at` datetime NOT NULL DEFAULT current_timestamp(),
  `status` enum('en_attente','disponible','honorée','annulée','expirée') NOT NULL DEFAULT 'en_attente',
  `notified_at` datetime DEFAULT NULL,
  `expires_at` datetime DEFAULT NULL
) ;

-- --------------------------------------------------------

--
-- Structure de la table `campuses`
--

CREATE TABLE `campuses` (
  `id` int(10) UNSIGNED NOT NULL,
  `code` varchar(20) NOT NULL,
  `name` varchar(150) NOT NULL,
  `address` varchar(255) DEFAULT NULL,
  `city` varchar(100) DEFAULT NULL,
  `province` varchar(100) DEFAULT NULL,
  `phone` varchar(30) DEFAULT NULL,
  `email` varchar(150) DEFAULT NULL,
  `director_id` int(10) UNSIGNED DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Déchargement des données de la table `campuses`
--

INSERT INTO `campuses` (`id`, `code`, `name`, `address`, `city`, `province`, `phone`, `email`, `director_id`, `is_active`, `created_at`, `updated_at`) VALUES
(1, 'BJM', 'Campus Bujumbura', 'Avenue de l\'Indépendance, N°12', 'Bujumbura', 'Bujumbura Mairie', '+257 22 22 22 22', 'bujumbura@uia.edu.bi', NULL, 1, '2026-10-20 16:28:13', '2026-10-20 16:28:13'),
(2, 'GIT', 'Campus Gitega', 'Quartier Administratif', 'Gitega', 'Gitega', '+257 22 40 40 40', 'gitega@uia.edu.bi', NULL, 1, '2026-10-20 16:28:13', '2026-10-20 16:28:13'),
(3, 'NGO', 'Campus Ngozi', 'Route Principale, N°5', 'Ngozi', 'Ngozi', '+257 22 30 30 30', 'ngozi@uia.edu.bi', NULL, 1, '2026-10-20 16:28:13', '2026-10-20 16:28:13');

-- --------------------------------------------------------

--
-- Structure de la table `cash_operations`
--

CREATE TABLE `cash_operations` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `cash_register_id` bigint(20) UNSIGNED NOT NULL,
  `type` enum('entrée','sortie') NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `motif` varchar(255) NOT NULL,
  `reference` varchar(50) DEFAULT NULL,
  `created_by` int(10) UNSIGNED NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ;

--
-- Déclencheurs `cash_operations`
--
DELIMITER $$
CREATE TRIGGER `trg_cash_operations_ai` AFTER INSERT ON `cash_operations` FOR EACH ROW BEGIN
  UPDATE `cash_register`
     SET `total_in` =`total_in` +IF(NEW.`type`='entrée',NEW.`amount`,0),
         `total_out`=`total_out`+IF(NEW.`type`='sortie',NEW.`amount`,0)
   WHERE `id`=NEW.`cash_register_id`;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_cash_operations_bi` BEFORE INSERT ON `cash_operations` FOR EACH ROW BEGIN
  IF (SELECT `status` FROM `cash_register` WHERE `id`=NEW.`cash_register_id`) <> 'ouverte' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='La caisse est fermée : opération refusée';
  END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Structure de la table `cash_register`
--

CREATE TABLE `cash_register` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `campus_id` int(10) UNSIGNED NOT NULL,
  `session_date` date NOT NULL,
  `opening_balance` decimal(12,2) NOT NULL DEFAULT 0.00,
  `closing_balance` decimal(12,2) DEFAULT NULL,
  `total_in` decimal(12,2) NOT NULL DEFAULT 0.00,
  `total_out` decimal(12,2) NOT NULL DEFAULT 0.00,
  `status` enum('ouverte','fermée') NOT NULL DEFAULT 'ouverte',
  `opened_by` int(10) UNSIGNED NOT NULL,
  `closed_by` int(10) UNSIGNED DEFAULT NULL,
  `opened_at` datetime NOT NULL DEFAULT current_timestamp(),
  `closed_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `class_sessions`
--

CREATE TABLE `class_sessions` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `timetable_id` int(10) UNSIGNED DEFAULT NULL,
  `course_id` int(10) UNSIGNED NOT NULL,
  `teacher_id` int(10) UNSIGNED NOT NULL,
  `campus_id` int(10) UNSIGNED NOT NULL,
  `room_id` int(10) UNSIGNED DEFAULT NULL,
  `session_date` date NOT NULL,
  `start_time` time NOT NULL,
  `end_time` time NOT NULL,
  `hours` decimal(5,2) GENERATED ALWAYS AS (round((time_to_sec(`end_time`) - time_to_sec(`start_time`)) / 3600,2)) STORED,
  `type` enum('CM','TD','TP') NOT NULL DEFAULT 'CM',
  `topic` varchar(255) DEFAULT NULL,
  `syllabus_id` int(10) UNSIGNED DEFAULT NULL,
  `status` enum('prévue','tenue','annulée','reportée') NOT NULL DEFAULT 'tenue',
  `payroll_status` enum('à_valider','validée','payée') NOT NULL DEFAULT 'à_valider',
  `validated_by` int(10) UNSIGNED DEFAULT NULL,
  `validated_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ;

-- --------------------------------------------------------

--
-- Structure de la table `courses`
--

CREATE TABLE `courses` (
  `id` int(10) UNSIGNED NOT NULL,
  `code` varchar(20) NOT NULL,
  `title` varchar(200) NOT NULL,
  `credits` tinyint(3) UNSIGNED NOT NULL DEFAULT 3,
  `program_id` int(10) UNSIGNED NOT NULL,
  `unit_id` int(10) UNSIGNED DEFAULT NULL,
  `semester_id` int(10) UNSIGNED DEFAULT NULL,
  `coefficient` decimal(4,2) NOT NULL DEFAULT 1.00,
  `hours_cm` smallint(5) UNSIGNED DEFAULT 0,
  `hours_td` smallint(5) UNSIGNED DEFAULT 0,
  `hours_tp` smallint(5) UNSIGNED DEFAULT 0,
  `hours_tpe` smallint(5) UNSIGNED DEFAULT 0,
  `hours_total` smallint(5) UNSIGNED GENERATED ALWAYS AS (coalesce(`hours_cm`,0) + coalesce(`hours_td`,0) + coalesce(`hours_tp`,0)) STORED,
  `course_type` enum('obligatoire','optionnel','libre') NOT NULL DEFAULT 'obligatoire',
  `is_active` tinyint(1) NOT NULL DEFAULT 1
) ;

-- --------------------------------------------------------

--
-- Structure de la table `course_assignments`
--

CREATE TABLE `course_assignments` (
  `id` int(10) UNSIGNED NOT NULL,
  `course_id` int(10) UNSIGNED NOT NULL,
  `teacher_id` int(10) UNSIGNED NOT NULL,
  `academic_year_id` int(10) UNSIGNED NOT NULL,
  `campus_id` int(10) UNSIGNED DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `course_results`
--

CREATE TABLE `course_results` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `student_id` int(10) UNSIGNED NOT NULL,
  `course_id` int(10) UNSIGNED NOT NULL,
  `academic_year_id` int(10) UNSIGNED NOT NULL,
  `semester_id` int(10) UNSIGNED NOT NULL,
  `session_no` tinyint(3) UNSIGNED NOT NULL DEFAULT 1,
  `average` decimal(5,2) DEFAULT NULL,
  `credits_earned` tinyint(3) UNSIGNED DEFAULT 0,
  `status` enum('validé','rattrapage','ajourné') DEFAULT NULL,
  `is_compensated` tinyint(1) NOT NULL DEFAULT 0,
  `validated_by` int(10) UNSIGNED DEFAULT NULL,
  `validated_at` datetime DEFAULT NULL
) ;

-- --------------------------------------------------------

--
-- Structure de la table `departments`
--

CREATE TABLE `departments` (
  `id` int(10) UNSIGNED NOT NULL,
  `code` varchar(20) NOT NULL,
  `name` varchar(150) NOT NULL,
  `faculty_id` int(10) UNSIGNED NOT NULL,
  `head_id` int(10) UNSIGNED DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `device_tokens`
--

CREATE TABLE `device_tokens` (
  `id` int(10) UNSIGNED NOT NULL,
  `user_id` int(10) UNSIGNED NOT NULL,
  `token` varchar(255) NOT NULL,
  `platform` enum('web','android','ios') NOT NULL DEFAULT 'web',
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `documents`
--

CREATE TABLE `documents` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `uuid` char(36) NOT NULL,
  `verification_code` char(12) DEFAULT NULL,
  `type` enum('relevé','certificat','diplôme','attestation','facture','autre','carte_étudiant','pv_délibération','attestation_réussite','attestation_inscription') NOT NULL,
  `student_id` int(10) UNSIGNED DEFAULT NULL,
  `user_id` int(10) UNSIGNED DEFAULT NULL,
  `title` varchar(200) NOT NULL,
  `file_path` varchar(255) NOT NULL,
  `file_size` int(10) UNSIGNED DEFAULT NULL,
  `mime_type` varchar(100) DEFAULT NULL,
  `issued_by` int(10) UNSIGNED DEFAULT NULL,
  `issued_at` datetime NOT NULL DEFAULT current_timestamp(),
  `is_archived` tinyint(1) NOT NULL DEFAULT 0,
  `archived_at` datetime DEFAULT NULL,
  `metadata` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL CHECK (json_valid(`metadata`))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `document_requirements`
--

CREATE TABLE `document_requirements` (
  `id` int(10) UNSIGNED NOT NULL,
  `document_type_id` smallint(5) UNSIGNED NOT NULL,
  `institution_type` enum('faculté','institut') DEFAULT NULL,
  `cycle` enum('licence','master','doctorat') DEFAULT NULL,
  `enrollment_type` enum('nouvelle','réinscription','redoublement','transfert') DEFAULT NULL,
  `foreign_only` tinyint(1) NOT NULL DEFAULT 0,
  `min_quantity` tinyint(3) UNSIGNED NOT NULL DEFAULT 1,
  `alt_group` varchar(30) DEFAULT NULL,
  `is_mandatory` tinyint(1) NOT NULL DEFAULT 1,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `notes` varchar(255) DEFAULT NULL
) ;

--
-- Déchargement des données de la table `document_requirements`
--

INSERT INTO `document_requirements` (`id`, `document_type_id`, `institution_type`, `cycle`, `enrollment_type`, `foreign_only`, `min_quantity`, `alt_group`, `is_mandatory`, `is_active`, `notes`) VALUES
(1, 6, NULL, 'doctorat', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(2, 6, NULL, 'master', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(3, 6, NULL, 'licence', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(4, 3, 'faculté', 'licence', 'nouvelle', 0, 1, 'DIPL_SEC', 1, 1, 'Ou Diplôme d\'État'),
(5, 10, NULL, NULL, 'réinscription', 0, 1, NULL, 1, 1, NULL),
(6, 5, NULL, 'doctorat', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(7, 5, NULL, 'master', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(8, 5, NULL, 'licence', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(9, 4, 'institut', 'licence', 'nouvelle', 0, 3, NULL, 1, 1, '3 bulletins exigés'),
(10, 8, NULL, 'doctorat', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(11, 8, NULL, 'master', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(12, 8, NULL, 'licence', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(13, 7, NULL, 'doctorat', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(14, 7, NULL, 'master', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(15, 7, NULL, 'licence', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(16, 15, NULL, 'doctorat', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(17, 15, NULL, 'master', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(18, 2, 'faculté', 'licence', 'nouvelle', 0, 1, 'DIPL_SEC', 1, 1, 'Ou attestation de réussite'),
(19, 11, NULL, 'doctorat', 'nouvelle', 0, 1, NULL, 1, 1, 'Diplôme de Master'),
(20, 11, NULL, 'master', 'nouvelle', 0, 1, NULL, 1, 1, 'Diplôme de Licence'),
(21, 19, 'faculté', 'licence', 'nouvelle', 1, 1, 'DIPL_SEC', 1, 1, 'Pour diplôme étranger'),
(22, 13, NULL, NULL, 'transfert', 0, 1, NULL, 1, 1, NULL),
(23, 13, NULL, 'doctorat', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(24, 13, NULL, 'master', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(25, 14, NULL, NULL, 'transfert', 0, 1, NULL, 1, 1, NULL),
(26, 17, NULL, NULL, 'nouvelle', 1, 1, NULL, 1, 1, NULL),
(27, 18, NULL, NULL, 'nouvelle', 1, 1, NULL, 1, 1, NULL),
(28, 1, NULL, NULL, 'transfert', 0, 1, NULL, 1, 1, NULL),
(29, 1, NULL, NULL, 'redoublement', 0, 1, NULL, 1, 1, NULL),
(30, 1, NULL, NULL, 'réinscription', 0, 1, NULL, 1, 1, NULL),
(31, 1, NULL, 'doctorat', 'nouvelle', 0, 2, NULL, 1, 1, NULL),
(32, 1, NULL, 'master', 'nouvelle', 0, 2, NULL, 1, 1, NULL),
(33, 1, NULL, 'licence', 'nouvelle', 0, 2, NULL, 1, 1, 'Nombre de photos à confirmer'),
(34, 9, NULL, NULL, 'transfert', 0, 1, NULL, 1, 1, NULL),
(35, 9, NULL, NULL, 'redoublement', 0, 1, NULL, 1, 1, NULL),
(36, 9, NULL, NULL, 'réinscription', 0, 1, NULL, 1, 1, NULL),
(37, 9, NULL, 'doctorat', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(38, 9, NULL, 'master', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(39, 9, NULL, 'licence', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(40, 16, NULL, 'doctorat', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(41, 12, NULL, NULL, 'transfert', 0, 1, NULL, 1, 1, NULL),
(42, 12, NULL, 'doctorat', 'nouvelle', 0, 1, NULL, 1, 1, NULL),
(43, 12, NULL, 'master', 'nouvelle', 0, 1, NULL, 1, 1, NULL);

-- --------------------------------------------------------

--
-- Structure de la table `document_types`
--

CREATE TABLE `document_types` (
  `id` smallint(5) UNSIGNED NOT NULL,
  `code` varchar(30) NOT NULL,
  `label` varchar(150) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `is_one_time` tinyint(1) NOT NULL DEFAULT 1,
  `has_expiry` tinyint(1) NOT NULL DEFAULT 0,
  `is_active` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Déchargement des données de la table `document_types`
--

INSERT INTO `document_types` (`id`, `code`, `label`, `description`, `is_one_time`, `has_expiry`, `is_active`) VALUES
(1, 'PHOTO_PASSEPORT', 'Photo passeport', 'Photo d\'identité format passeport (fond clair)', 0, 0, 1),
(2, 'DIPLOME_ETAT', 'Diplôme d\'État (humanités)', 'Copie légalisée du Diplôme d\'État', 1, 0, 1),
(3, 'ATTEST_EXAMEN_ETAT', 'Attestation de réussite à l\'Examen d\'État', 'Délivrée en attendant le diplôme', 1, 0, 1),
(4, 'BULLETIN', 'Bulletin scolaire', 'Bulletins des dernières années du secondaire', 1, 0, 1),
(5, 'BONNE_CONDUITE', 'Attestation de bonne conduite, vie et mœurs', 'Délivrée par l\'administration communale ou l\'école', 1, 1, 1),
(6, 'ACTE_NAISSANCE', 'Acte de naissance', NULL, 1, 0, 1),
(7, 'CNI_COPIE', 'Copie de la carte nationale d\'identité', NULL, 1, 1, 1),
(8, 'CERT_MEDICAL', 'Certificat médical d\'aptitude', NULL, 0, 1, 1),
(9, 'PREUVE_PAIEMENT', 'Preuve de paiement des frais d\'inscription', 'Bordereau bancaire, reçu de caisse ou preuve mobile money', 0, 0, 1),
(10, 'ATTEST_REUSSITE_ANNEE', 'Attestation de réussite de l\'année précédente', 'Pour la réinscription', 0, 0, 1),
(11, 'DIPLOME_PREC', 'Diplôme du cycle précédent', 'Licence pour entrer en Master, Master pour entrer en Doctorat', 1, 0, 1),
(12, 'RELEVE_NOTES_PREC', 'Relevé de notes du cycle / de l\'établissement précédent', NULL, 1, 0, 1),
(13, 'LETTRE_DEMANDE', 'Lettre de demande d\'inscription / de transfert', NULL, 0, 0, 1),
(14, 'LETTRE_EXEAT', 'Lettre d\'exeat de l\'établissement d\'origine', 'Pour les transferts', 0, 0, 1),
(15, 'CV', 'Curriculum vitae', 'Master et Doctorat', 1, 0, 1),
(16, 'PROJET_RECHERCHE', 'Projet de recherche', 'Doctorat', 1, 0, 1),
(17, 'PASSEPORT_COPIE', 'Copie du passeport', 'Étudiants étrangers', 1, 1, 1),
(18, 'PERMIS_SEJOUR', 'Visa ou permis de séjour', 'Étudiants étrangers', 0, 1, 1),
(19, 'EQUIVALENCE_DIPLOME', 'Équivalence du diplôme du secondaire', 'Étudiants ayant un diplôme étranger', 1, 0, 1);

-- --------------------------------------------------------

--
-- Structure de la table `enrollments`
--

CREATE TABLE `enrollments` (
  `id` int(10) UNSIGNED NOT NULL,
  `student_id` int(10) UNSIGNED NOT NULL,
  `program_id` int(10) UNSIGNED NOT NULL,
  `academic_year_id` int(10) UNSIGNED NOT NULL,
  `campus_id` int(10) UNSIGNED NOT NULL,
  `level` enum('L1','L2','L3','M1','M2','D') NOT NULL,
  `enrollment_type` enum('nouvelle','réinscription','redoublement','transfert') NOT NULL DEFAULT 'nouvelle',
  `enrollment_date` date NOT NULL DEFAULT curdate(),
  `status` enum('en_attente','validée','annulée') NOT NULL DEFAULT 'en_attente',
  `validated_by` int(10) UNSIGNED DEFAULT NULL,
  `validated_at` datetime DEFAULT NULL,
  `documents_waiver_until` date DEFAULT NULL,
  `documents_waiver_reason` varchar(255) DEFAULT NULL,
  `documents_waiver_by` int(10) UNSIGNED DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Déclencheurs `enrollments`
--
DELIMITER $$
CREATE TRIGGER `trg_enrollments_bi` BEFORE INSERT ON `enrollments` FOR EACH ROW BEGIN
  DECLARE v_enforce VARCHAR(10);
  IF NEW.`status`='validée' THEN
    SELECT `value` INTO v_enforce FROM `settings` WHERE `key_name`='enforce_enrollment_documents';
    IF COALESCE(v_enforce,'1')='1'
       AND NOT (NEW.`documents_waiver_until` IS NOT NULL AND NEW.`documents_waiver_until`>=CURDATE()) THEN
      IF fn_missing_docs_count(NEW.`student_id`,NEW.`program_id`,NEW.`academic_year_id`,
                               NEW.`level`,NEW.`enrollment_type`)>0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Dossier incomplet : pièces manquantes ou dérogation requise';
      END IF;
    END IF;
  END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_enrollments_bu` BEFORE UPDATE ON `enrollments` FOR EACH ROW BEGIN
  DECLARE v_enforce VARCHAR(10);
  IF NEW.`status`='validée' AND OLD.`status`<>'validée' THEN
    SELECT `value` INTO v_enforce FROM `settings` WHERE `key_name`='enforce_enrollment_documents';
    IF COALESCE(v_enforce,'1')='1'
       AND NOT (NEW.`documents_waiver_until` IS NOT NULL AND NEW.`documents_waiver_until`>=CURDATE()) THEN
      IF fn_missing_docs_count(NEW.`student_id`,NEW.`program_id`,NEW.`academic_year_id`,
                               NEW.`level`,NEW.`enrollment_type`)>0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Dossier incomplet : pièces manquantes ou dérogation requise';
      END IF;
    END IF;
  END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Structure de la table `enrollment_documents`
--

CREATE TABLE `enrollment_documents` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `student_id` int(10) UNSIGNED DEFAULT NULL,
  `admission_id` int(10) UNSIGNED DEFAULT NULL,
  `enrollment_id` int(10) UNSIGNED DEFAULT NULL,
  `academic_year_id` int(10) UNSIGNED DEFAULT NULL,
  `document_type_id` smallint(5) UNSIGNED NOT NULL,
  `quantity` tinyint(3) UNSIGNED NOT NULL DEFAULT 1,
  `reference_no` varchar(100) DEFAULT NULL,
  `issuer` varchar(150) DEFAULT NULL,
  `issued_date` date DEFAULT NULL,
  `expires_at` date DEFAULT NULL,
  `document_id` bigint(20) UNSIGNED DEFAULT NULL,
  `file_path` varchar(255) DEFAULT NULL,
  `status` enum('en_attente','reçu','validé','rejeté') NOT NULL DEFAULT 'reçu',
  `rejection_reason` varchar(255) DEFAULT NULL,
  `received_by` int(10) UNSIGNED DEFAULT NULL,
  `received_at` datetime NOT NULL DEFAULT current_timestamp(),
  `verified_by` int(10) UNSIGNED DEFAULT NULL,
  `verified_at` datetime DEFAULT NULL
) ;

--
-- Déclencheurs `enrollment_documents`
--
DELIMITER $$
CREATE TRIGGER `trg_enroll_docs_ai` AFTER INSERT ON `enrollment_documents` FOR EACH ROW BEGIN
  IF NEW.`student_id` IS NOT NULL AND NEW.`file_path` IS NOT NULL AND NEW.`status` IN ('reçu','validé')
     AND (SELECT `code` FROM `document_types` WHERE `id`=NEW.`document_type_id`)='PHOTO_PASSEPORT' THEN
    UPDATE `students` SET `photo`=NEW.`file_path` WHERE `id`=NEW.`student_id`;
  END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_enroll_docs_bi` BEFORE INSERT ON `enrollment_documents` FOR EACH ROW BEGIN
  IF NEW.`status`='rejeté' AND (NEW.`rejection_reason` IS NULL OR NEW.`rejection_reason`='') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Un motif est obligatoire pour rejeter une pièce';
  END IF;
  IF NEW.`status` IN ('validé','rejeté') AND NEW.`verified_at` IS NULL THEN
    SET NEW.`verified_at`=NOW();
  END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_enroll_docs_bu` BEFORE UPDATE ON `enrollment_documents` FOR EACH ROW BEGIN
  IF NEW.`status`<>OLD.`status` AND NEW.`status` IN ('validé','rejeté') THEN
    SET NEW.`verified_at`=NOW();
  END IF;
  IF NEW.`status`='rejeté' AND (NEW.`rejection_reason` IS NULL OR NEW.`rejection_reason`='') THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Un motif est obligatoire pour rejeter une pièce';
  END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Structure de la table `evaluations`
--

CREATE TABLE `evaluations` (
  `id` int(10) UNSIGNED NOT NULL,
  `course_id` int(10) UNSIGNED NOT NULL,
  `teacher_id` int(10) UNSIGNED NOT NULL,
  `academic_year_id` int(10) UNSIGNED DEFAULT NULL,
  `type` enum('TD','TP','Interrogation','Examen','Rattrapage') NOT NULL,
  `title` varchar(150) DEFAULT NULL,
  `max_score` decimal(5,2) NOT NULL DEFAULT 20.00,
  `weight` decimal(5,2) NOT NULL DEFAULT 1.00,
  `evaluation_date` date DEFAULT NULL,
  `is_published` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ;

--
-- Déclencheurs `evaluations`
--
DELIMITER $$
CREATE TRIGGER `trg_evaluations_bi` BEFORE INSERT ON `evaluations` FOR EACH ROW BEGIN
  IF NEW.`academic_year_id` IS NULL THEN
    SET NEW.`academic_year_id` = (SELECT `id` FROM `academic_years` WHERE `is_current`=1 LIMIT 1);
  END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Structure de la table `exam_schedules`
--

CREATE TABLE `exam_schedules` (
  `id` int(10) UNSIGNED NOT NULL,
  `evaluation_id` int(10) UNSIGNED DEFAULT NULL,
  `course_id` int(10) UNSIGNED NOT NULL,
  `semester_id` int(10) UNSIGNED NOT NULL,
  `session_no` tinyint(3) UNSIGNED NOT NULL DEFAULT 1,
  `campus_id` int(10) UNSIGNED NOT NULL,
  `room_id` int(10) UNSIGNED DEFAULT NULL,
  `exam_date` date NOT NULL,
  `start_time` time NOT NULL,
  `end_time` time NOT NULL,
  `supervisor_id` int(10) UNSIGNED DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ;

-- --------------------------------------------------------

--
-- Structure de la table `faculties`
--

CREATE TABLE `faculties` (
  `id` int(10) UNSIGNED NOT NULL,
  `code` varchar(20) NOT NULL,
  `name` varchar(150) NOT NULL,
  `institution_type` enum('faculté','institut') NOT NULL DEFAULT 'faculté',
  `dean_id` int(10) UNSIGNED DEFAULT NULL,
  `campus_id` int(10) UNSIGNED DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `fee_structures`
--

CREATE TABLE `fee_structures` (
  `id` int(10) UNSIGNED NOT NULL,
  `program_id` int(10) UNSIGNED NOT NULL,
  `academic_year_id` int(10) UNSIGNED NOT NULL,
  `level` enum('L1','L2','L3','M1','M2','D') NOT NULL,
  `amount` decimal(12,2) NOT NULL DEFAULT 0.00,
  `currency` char(3) NOT NULL DEFAULT 'BIF',
  `description` varchar(255) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ;

-- --------------------------------------------------------

--
-- Structure de la table `grades`
--

CREATE TABLE `grades` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `evaluation_id` int(10) UNSIGNED NOT NULL,
  `student_id` int(10) UNSIGNED NOT NULL,
  `score` decimal(5,2) DEFAULT NULL,
  `is_absent` tinyint(1) NOT NULL DEFAULT 0,
  `comment` varchar(255) DEFAULT NULL,
  `entered_by` int(10) UNSIGNED DEFAULT NULL,
  `entered_at` datetime NOT NULL DEFAULT current_timestamp()
) ;

--
-- Déclencheurs `grades`
--
DELIMITER $$
CREATE TRIGGER `trg_grades_au` AFTER UPDATE ON `grades` FOR EACH ROW BEGIN
  IF NOT (OLD.`score`<=>NEW.`score`) OR OLD.`is_absent`<>NEW.`is_absent` THEN
    INSERT INTO `grade_history`
      (`grade_id`,`evaluation_id`,`student_id`,`old_score`,`new_score`,`old_absent`,`new_absent`,`changed_by`)
    VALUES (OLD.`id`,OLD.`evaluation_id`,OLD.`student_id`,OLD.`score`,NEW.`score`,
            OLD.`is_absent`,NEW.`is_absent`,NEW.`entered_by`);
  END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_grades_bi` BEFORE INSERT ON `grades` FOR EACH ROW BEGIN
  DECLARE v_max DECIMAL(5,2);
  SELECT `max_score` INTO v_max FROM `evaluations` WHERE `id`=NEW.`evaluation_id`;
  IF NEW.`is_absent`=1 THEN SET NEW.`score`=NULL;
  ELSEIF NEW.`score` IS NOT NULL AND (NEW.`score`<0 OR NEW.`score`>v_max) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Note hors barème de l''évaluation';
  END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_grades_bu` BEFORE UPDATE ON `grades` FOR EACH ROW BEGIN
  DECLARE v_max DECIMAL(5,2);
  SELECT `max_score` INTO v_max FROM `evaluations` WHERE `id`=NEW.`evaluation_id`;
  IF NEW.`is_absent`=1 THEN SET NEW.`score`=NULL;
  ELSEIF NEW.`score` IS NOT NULL AND (NEW.`score`<0 OR NEW.`score`>v_max) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Note hors barème de l''évaluation';
  END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Structure de la table `grade_appeals`
--

CREATE TABLE `grade_appeals` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `evaluation_id` int(10) UNSIGNED NOT NULL,
  `student_id` int(10) UNSIGNED NOT NULL,
  `reason` text NOT NULL,
  `status` enum('déposée','en_cours','acceptée','rejetée') NOT NULL DEFAULT 'déposée',
  `new_score` decimal(5,2) DEFAULT NULL,
  `response` text DEFAULT NULL,
  `handled_by` int(10) UNSIGNED DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `handled_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `grade_history`
--

CREATE TABLE `grade_history` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `grade_id` bigint(20) UNSIGNED NOT NULL,
  `evaluation_id` int(10) UNSIGNED NOT NULL,
  `student_id` int(10) UNSIGNED NOT NULL,
  `old_score` decimal(5,2) DEFAULT NULL,
  `new_score` decimal(5,2) DEFAULT NULL,
  `old_absent` tinyint(1) NOT NULL DEFAULT 0,
  `new_absent` tinyint(1) NOT NULL DEFAULT 0,
  `changed_by` int(10) UNSIGNED DEFAULT NULL,
  `changed_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `grade_mentions`
--

CREATE TABLE `grade_mentions` (
  `id` tinyint(3) UNSIGNED NOT NULL,
  `code` varchar(40) NOT NULL,
  `label` varchar(80) NOT NULL,
  `min_score` decimal(5,2) NOT NULL,
  `max_score` decimal(5,2) NOT NULL,
  `is_pass` tinyint(1) NOT NULL DEFAULT 1
) ;

--
-- Déchargement des données de la table `grade_mentions`
--

INSERT INTO `grade_mentions` (`id`, `code`, `label`, `min_score`, `max_score`, `is_pass`) VALUES
(1, 'INSUFFISANT', 'Insuffisant / Ajourné', 0.00, 9.99, 0),
(2, 'PASSABLE', 'Passable', 10.00, 11.99, 1),
(3, 'SATISFACTION', 'Satisfaction', 12.00, 13.99, 1),
(4, 'DISTINCTION', 'Distinction', 14.00, 15.99, 1),
(5, 'GRANDE_DISTINCTION', 'Grande distinction', 16.00, 17.99, 1),
(6, 'PLUS_GRANDE_DISTINCTION', 'Plus grande distinction', 18.00, 20.00, 1);

-- --------------------------------------------------------

--
-- Structure de la table `internships`
--

CREATE TABLE `internships` (
  `id` int(10) UNSIGNED NOT NULL,
  `student_id` int(10) UNSIGNED NOT NULL,
  `academic_year_id` int(10) UNSIGNED NOT NULL,
  `organization` varchar(200) NOT NULL,
  `city` varchar(100) DEFAULT NULL,
  `academic_supervisor_id` int(10) UNSIGNED DEFAULT NULL,
  `org_supervisor_name` varchar(150) DEFAULT NULL,
  `org_supervisor_phone` varchar(30) DEFAULT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `status` enum('proposé','validé','en_cours','terminé','annulé') NOT NULL DEFAULT 'proposé',
  `score` decimal(5,2) DEFAULT NULL,
  `credits` tinyint(3) UNSIGNED DEFAULT NULL,
  `report_document_id` bigint(20) UNSIGNED DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ;

-- --------------------------------------------------------

--
-- Structure de la table `invoices`
--

CREATE TABLE `invoices` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `reference` varchar(30) NOT NULL,
  `student_id` int(10) UNSIGNED NOT NULL,
  `academic_year_id` int(10) UNSIGNED NOT NULL,
  `level` enum('L1','L2','L3','M1','M2','D') NOT NULL,
  `amount_due` decimal(12,2) NOT NULL,
  `amount_paid` decimal(12,2) NOT NULL DEFAULT 0.00,
  `currency` char(3) NOT NULL DEFAULT 'BIF',
  `due_date` date DEFAULT NULL,
  `status` enum('impayée','partielle','payée','annulée') NOT NULL DEFAULT 'impayée',
  `created_by` int(10) UNSIGNED DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ;

-- --------------------------------------------------------

--
-- Structure de la table `invoice_installments`
--

CREATE TABLE `invoice_installments` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `invoice_id` bigint(20) UNSIGNED NOT NULL,
  `installment_no` tinyint(3) UNSIGNED NOT NULL,
  `due_date` date NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `paid_amount` decimal(12,2) NOT NULL DEFAULT 0.00,
  `status` enum('impayée','partielle','payée') NOT NULL DEFAULT 'impayée'
) ;

-- --------------------------------------------------------

--
-- Structure de la table `job_titles`
--

CREATE TABLE `job_titles` (
  `id` int(10) UNSIGNED NOT NULL,
  `code` varchar(30) NOT NULL,
  `label` varchar(150) NOT NULL,
  `staff_category` enum('enseignant','administratif','technique','appui','direction') NOT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Déchargement des données de la table `job_titles`
--

INSERT INTO `job_titles` (`id`, `code`, `label`, `staff_category`, `is_active`) VALUES
(1, 'RECTEUR', 'Recteur', 'direction', 1),
(2, 'SG', 'Secrétaire Général', 'direction', 1),
(3, 'DAF', 'Directeur Administratif et Financier', 'direction', 1),
(4, 'DIR_CAMPUS', 'Directeur de Campus', 'direction', 1),
(5, 'DOYEN', 'Doyen de Faculté', 'direction', 1),
(6, 'CHEF_DEPT', 'Chef de Département', 'enseignant', 1),
(7, 'PROFESSEUR', 'Professeur', 'enseignant', 1),
(8, 'CHARGE_COURS', 'Chargé de cours', 'enseignant', 1),
(9, 'ASSISTANT', 'Assistant', 'enseignant', 1),
(10, 'SECRETAIRE', 'Secrétaire', 'administratif', 1),
(11, 'AGENT_SCOL', 'Agent de scolarité', 'administratif', 1),
(12, 'COMPTABLE', 'Comptable', 'administratif', 1),
(13, 'CAISSIER', 'Caissier', 'administratif', 1),
(14, 'BIBLIOTHECAIRE', 'Bibliothécaire', 'administratif', 1),
(15, 'TECH_INFO', 'Technicien informatique', 'technique', 1),
(16, 'TECH_LABO', 'Technicien de laboratoire', 'technique', 1),
(17, 'CHAUFFEUR', 'Chauffeur', 'appui', 1),
(18, 'GARDIEN', 'Gardien', 'appui', 1),
(19, 'ENTRETIEN', 'Agent d\'entretien', 'appui', 1);

-- --------------------------------------------------------

--
-- Structure de la table `juries`
--

CREATE TABLE `juries` (
  `id` int(10) UNSIGNED NOT NULL,
  `academic_year_id` int(10) UNSIGNED NOT NULL,
  `campus_id` int(10) UNSIGNED NOT NULL,
  `program_id` int(10) UNSIGNED NOT NULL,
  `level` enum('L1','L2','L3','M1','M2','D') NOT NULL,
  `session_no` tinyint(3) UNSIGNED NOT NULL DEFAULT 1,
  `president_id` int(10) UNSIGNED DEFAULT NULL,
  `secretary_id` int(10) UNSIGNED DEFAULT NULL,
  `deliberation_date` date DEFAULT NULL,
  `status` enum('préparation','en_délibération','clôturé') NOT NULL DEFAULT 'préparation',
  `pv_document_id` bigint(20) UNSIGNED DEFAULT NULL,
  `notes` text DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `jury_decisions`
--

CREATE TABLE `jury_decisions` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `jury_id` int(10) UNSIGNED NOT NULL,
  `student_id` int(10) UNSIGNED NOT NULL,
  `year_result_id` bigint(20) UNSIGNED DEFAULT NULL,
  `decision` enum('admis','admis_avec_dettes','ajourné','redoublement','exclu','diplômé') NOT NULL,
  `mention_label` varchar(80) DEFAULT NULL,
  `is_override` tinyint(1) NOT NULL DEFAULT 0,
  `remark` text DEFAULT NULL,
  `decided_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `jury_members`
--

CREATE TABLE `jury_members` (
  `jury_id` int(10) UNSIGNED NOT NULL,
  `user_id` int(10) UNSIGNED NOT NULL,
  `role` enum('président','secrétaire','membre') NOT NULL DEFAULT 'membre'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `leave_requests`
--

CREATE TABLE `leave_requests` (
  `id` int(10) UNSIGNED NOT NULL,
  `user_id` int(10) UNSIGNED NOT NULL,
  `leave_type_id` smallint(5) UNSIGNED NOT NULL,
  `start_date` date NOT NULL,
  `end_date` date NOT NULL,
  `days_count` smallint(5) UNSIGNED GENERATED ALWAYS AS (to_days(`end_date`) - to_days(`start_date`) + 1) STORED,
  `reason` varchar(255) DEFAULT NULL,
  `status` enum('en_attente','approuvé','refusé','annulé') NOT NULL DEFAULT 'en_attente',
  `approved_by` int(10) UNSIGNED DEFAULT NULL,
  `decided_at` datetime DEFAULT NULL,
  `decision_note` varchar(255) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ;

--
-- Déclencheurs `leave_requests`
--
DELIMITER $$
CREATE TRIGGER `trg_leave_requests_bi` BEFORE INSERT ON `leave_requests` FOR EACH ROW BEGIN
  DECLARE v_cap SMALLINT UNSIGNED; DECLARE v_used INT DEFAULT 0;
  IF NEW.`end_date`<NEW.`start_date` THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='La date de fin précède la date de début';
  END IF;
  IF EXISTS (SELECT 1 FROM `leave_requests` l
              WHERE l.`user_id`=NEW.`user_id` AND l.`status` IN ('en_attente','approuvé')
                AND l.`start_date`<=NEW.`end_date` AND l.`end_date`>=NEW.`start_date`) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Cette période chevauche un autre congé de la même personne';
  END IF;
  SELECT `days_per_year` INTO v_cap FROM `leave_types` WHERE `id`=NEW.`leave_type_id`;
  IF v_cap IS NOT NULL THEN
    SELECT COALESCE(SUM(DATEDIFF(`end_date`,`start_date`)+1),0) INTO v_used FROM `leave_requests`
     WHERE `user_id`=NEW.`user_id` AND `leave_type_id`=NEW.`leave_type_id`
       AND `status` IN ('en_attente','approuvé') AND YEAR(`start_date`)=YEAR(NEW.`start_date`);
    IF v_used+DATEDIFF(NEW.`end_date`,NEW.`start_date`)+1>v_cap THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Solde de congé insuffisant pour cette année';
    END IF;
  END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_leave_requests_bu` BEFORE UPDATE ON `leave_requests` FOR EACH ROW BEGIN
  IF NEW.`status`<>OLD.`status` AND NEW.`status` IN ('approuvé','refusé') THEN
    SET NEW.`decided_at`=NOW();
  END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Structure de la table `leave_types`
--

CREATE TABLE `leave_types` (
  `id` smallint(5) UNSIGNED NOT NULL,
  `code` varchar(20) NOT NULL,
  `label` varchar(100) NOT NULL,
  `days_per_year` smallint(5) UNSIGNED DEFAULT NULL,
  `is_paid` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Déchargement des données de la table `leave_types`
--

INSERT INTO `leave_types` (`id`, `code`, `label`, `days_per_year`, `is_paid`) VALUES
(1, 'ANNUEL', 'Congé annuel', 30, 1),
(2, 'MALADIE', 'Congé de maladie', NULL, 1),
(3, 'MATERNITE', 'Congé de maternité', NULL, 1),
(4, 'PATERNITE', 'Congé de paternité', NULL, 1),
(5, 'CIRCONSTANCE', 'Congé pour événement familial', NULL, 1),
(6, 'FORMATION', 'Congé de formation', NULL, 1),
(7, 'SANS_SOLDE', 'Congé sans solde', NULL, 0);

-- --------------------------------------------------------

--
-- Structure de la table `library_fines`
--

CREATE TABLE `library_fines` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `loan_id` bigint(20) UNSIGNED NOT NULL,
  `student_id` int(10) UNSIGNED DEFAULT NULL,
  `user_id` int(10) UNSIGNED DEFAULT NULL,
  `days_late` smallint(5) UNSIGNED NOT NULL DEFAULT 0,
  `amount` decimal(10,2) NOT NULL,
  `currency` char(3) NOT NULL DEFAULT 'BIF',
  `reason` enum('retard','perte','dégradation') NOT NULL DEFAULT 'retard',
  `status` enum('impayée','payée','annulée') NOT NULL DEFAULT 'impayée',
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `paid_at` datetime DEFAULT NULL,
  `payment_ref` varchar(100) DEFAULT NULL,
  `handled_by` int(10) UNSIGNED DEFAULT NULL,
  `notes` varchar(255) DEFAULT NULL
) ;

-- --------------------------------------------------------

--
-- Structure de la table `library_visits`
--

CREATE TABLE `library_visits` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `campus_id` int(10) UNSIGNED NOT NULL,
  `student_id` int(10) UNSIGNED DEFAULT NULL,
  `user_id` int(10) UNSIGNED DEFAULT NULL,
  `entered_at` datetime NOT NULL DEFAULT current_timestamp(),
  `left_at` datetime DEFAULT NULL,
  `purpose` enum('lecture','emprunt','recherche','informatique','autre') NOT NULL DEFAULT 'lecture'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `loan_policies`
--

CREATE TABLE `loan_policies` (
  `borrower_type` enum('etudiant','enseignant','personnel') NOT NULL,
  `max_loans` tinyint(3) UNSIGNED NOT NULL DEFAULT 3,
  `loan_days` smallint(5) UNSIGNED NOT NULL DEFAULT 14,
  `max_renewals` tinyint(3) UNSIGNED NOT NULL DEFAULT 1,
  `fine_per_day` decimal(10,2) NOT NULL DEFAULT 0.00,
  `currency` char(3) NOT NULL DEFAULT 'BIF',
  `block_if_unpaid_fines` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Déchargement des données de la table `loan_policies`
--

INSERT INTO `loan_policies` (`borrower_type`, `max_loans`, `loan_days`, `max_renewals`, `fine_per_day`, `currency`, `block_if_unpaid_fines`) VALUES
('etudiant', 3, 14, 1, 200.00, 'BIF', 1),
('enseignant', 5, 30, 2, 200.00, 'BIF', 1),
('personnel', 3, 14, 1, 200.00, 'BIF', 1);

-- --------------------------------------------------------

--
-- Structure de la table `login_logs`
--

CREATE TABLE `login_logs` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `user_id` int(10) UNSIGNED DEFAULT NULL,
  `user_name` varchar(100) DEFAULT NULL,
  `ip_address` varchar(45) DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  `status` enum('success','failed') NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `messages`
--

CREATE TABLE `messages` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `sender_id` int(10) UNSIGNED NOT NULL,
  `recipient_id` int(10) UNSIGNED NOT NULL,
  `subject` varchar(200) DEFAULT NULL,
  `body` text NOT NULL,
  `is_read` tinyint(1) NOT NULL DEFAULT 0,
  `read_at` datetime DEFAULT NULL,
  `parent_id` bigint(20) UNSIGNED DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `notifications`
--

CREATE TABLE `notifications` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `user_id` int(10) UNSIGNED NOT NULL,
  `type` varchar(50) NOT NULL,
  `title` varchar(200) NOT NULL,
  `body` text DEFAULT NULL,
  `link` varchar(255) DEFAULT NULL,
  `is_read` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `parent_students`
--

CREATE TABLE `parent_students` (
  `parent_user_id` int(10) UNSIGNED NOT NULL,
  `student_id` int(10) UNSIGNED NOT NULL,
  `relationship` enum('père','mère','tuteur','autre') NOT NULL DEFAULT 'tuteur',
  `is_financial_responsible` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `password_resets`
--

CREATE TABLE `password_resets` (
  `id` int(10) UNSIGNED NOT NULL,
  `email` varchar(150) NOT NULL,
  `token` varchar(255) NOT NULL,
  `expires_at` datetime NOT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `payments`
--

CREATE TABLE `payments` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `reference` varchar(30) NOT NULL,
  `invoice_id` bigint(20) UNSIGNED NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `currency` char(3) NOT NULL DEFAULT 'BIF',
  `method` enum('espèces','virement','mobile_money','chèque','carte') NOT NULL,
  `mobile_operator` varchar(50) DEFAULT NULL,
  `bank_name` varchar(100) DEFAULT NULL,
  `slip_number` varchar(50) DEFAULT NULL,
  `transaction_ref` varchar(100) DEFAULT NULL,
  `cash_register_id` bigint(20) UNSIGNED DEFAULT NULL,
  `paid_at` datetime NOT NULL DEFAULT current_timestamp(),
  `receipt_no` varchar(50) DEFAULT NULL,
  `received_by` int(10) UNSIGNED DEFAULT NULL,
  `notes` text DEFAULT NULL
) ;

--
-- Déclencheurs `payments`
--
DELIMITER $$
CREATE TRIGGER `trg_payments_ad` AFTER DELETE ON `payments` FOR EACH ROW BEGIN
  UPDATE `invoices` SET `amount_paid`=`amount_paid`-OLD.`amount` WHERE `id`=OLD.`invoice_id`;
  UPDATE `invoices`
     SET `status`=CASE WHEN `status`='annulée' THEN `status`
                       WHEN `amount_paid`>=`amount_due` THEN 'payée'
                       WHEN `amount_paid`>0 THEN 'partielle'
                       ELSE 'impayée' END
   WHERE `id`=OLD.`invoice_id`;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_payments_ai` AFTER INSERT ON `payments` FOR EACH ROW BEGIN
  UPDATE `invoices` SET `amount_paid`=`amount_paid`+NEW.`amount` WHERE `id`=NEW.`invoice_id`;
  UPDATE `invoices`
     SET `status`=CASE WHEN `status`='annulée' THEN `status`
                       WHEN `amount_paid`>=`amount_due` THEN 'payée'
                       WHEN `amount_paid`>0 THEN 'partielle'
                       ELSE 'impayée' END
   WHERE `id`=NEW.`invoice_id`;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_payments_au` AFTER UPDATE ON `payments` FOR EACH ROW BEGIN
  IF NEW.`amount`<>OLD.`amount` THEN
    UPDATE `invoices` SET `amount_paid`=`amount_paid`-OLD.`amount`+NEW.`amount` WHERE `id`=NEW.`invoice_id`;
    UPDATE `invoices`
       SET `status`=CASE WHEN `status`='annulée' THEN `status`
                         WHEN `amount_paid`>=`amount_due` THEN 'payée'
                         WHEN `amount_paid`>0 THEN 'partielle'
                         ELSE 'impayée' END
     WHERE `id`=NEW.`invoice_id`;
  END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_payments_bi` BEFORE INSERT ON `payments` FOR EACH ROW BEGIN
  DECLARE v_rest DECIMAL(12,2); DECLARE v_status VARCHAR(20);
  SELECT (`amount_due`-`amount_paid`),`status` INTO v_rest,v_status FROM `invoices` WHERE `id`=NEW.`invoice_id`;
  IF v_status='annulée' THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Paiement impossible : facture annulée'; END IF;
  IF NEW.`amount`>v_rest THEN SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Paiement supérieur au solde restant'; END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Structure de la table `payroll_periods`
--

CREATE TABLE `payroll_periods` (
  `id` int(10) UNSIGNED NOT NULL,
  `period_month` date NOT NULL,
  `label` varchar(50) NOT NULL,
  `status` enum('ouverte','calculée','validée','payée') NOT NULL DEFAULT 'ouverte',
  `created_by` int(10) UNSIGNED DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `payroll_rules`
--

CREATE TABLE `payroll_rules` (
  `id` int(10) UNSIGNED NOT NULL,
  `code` varchar(30) NOT NULL,
  `label` varchar(150) NOT NULL,
  `kind` enum('gain','retenue') NOT NULL,
  `calc` enum('pourcentage','fixe','barème') NOT NULL DEFAULT 'pourcentage',
  `value` decimal(12,4) NOT NULL DEFAULT 0.0000,
  `base` enum('base','brut') NOT NULL DEFAULT 'base',
  `applies_to` enum('tous','enseignant','administratif','technique','appui','direction') NOT NULL DEFAULT 'tous',
  `is_active` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Déchargement des données de la table `payroll_rules`
--

INSERT INTO `payroll_rules` (`id`, `code`, `label`, `kind`, `calc`, `value`, `base`, `applies_to`, `is_active`) VALUES
(1, 'INSS_EMPLOYE', 'Cotisation INSS (part salariale) - TAUX À RENSEIGNER', 'retenue', 'pourcentage', 0.0000, 'base', 'tous', 0),
(2, 'IPR', 'Impôt professionnel sur rémunérations - BARÈME À RENSEIGNER', 'retenue', 'barème', 0.0000, 'brut', 'tous', 0),
(3, 'PRIME_TRANSPORT', 'Prime de transport - MONTANT À RENSEIGNER', 'gain', 'fixe', 0.0000, 'base', 'tous', 0),
(4, 'PRIME_LOGEMENT', 'Indemnité de logement - MONTANT À RENSEIGNER', 'gain', 'fixe', 0.0000, 'base', 'tous', 0);

-- --------------------------------------------------------

--
-- Structure de la table `payroll_tax_brackets`
--

CREATE TABLE `payroll_tax_brackets` (
  `id` int(10) UNSIGNED NOT NULL,
  `rule_id` int(10) UNSIGNED NOT NULL,
  `from_amount` decimal(12,2) NOT NULL,
  `to_amount` decimal(12,2) DEFAULT NULL,
  `rate` decimal(5,2) NOT NULL
) ;

-- --------------------------------------------------------

--
-- Structure de la table `payslips`
--

CREATE TABLE `payslips` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `period_id` int(10) UNSIGNED NOT NULL,
  `user_id` int(10) UNSIGNED NOT NULL,
  `contract_id` int(10) UNSIGNED DEFAULT NULL,
  `base_salary` decimal(12,2) NOT NULL DEFAULT 0.00,
  `vacation_hours` decimal(7,2) NOT NULL DEFAULT 0.00,
  `vacation_amount` decimal(12,2) NOT NULL DEFAULT 0.00,
  `total_gains` decimal(12,2) NOT NULL DEFAULT 0.00,
  `total_deductions` decimal(12,2) NOT NULL DEFAULT 0.00,
  `net_pay` decimal(12,2) NOT NULL DEFAULT 0.00,
  `currency` char(3) NOT NULL DEFAULT 'BIF',
  `status` enum('brouillon','validé','payé') NOT NULL DEFAULT 'brouillon',
  `payment_method` enum('virement','espèces','mobile_money','chèque') DEFAULT NULL,
  `paid_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `payslip_items`
--

CREATE TABLE `payslip_items` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `payslip_id` bigint(20) UNSIGNED NOT NULL,
  `rule_id` int(10) UNSIGNED DEFAULT NULL,
  `kind` enum('gain','retenue') NOT NULL,
  `label` varchar(150) NOT NULL,
  `amount` decimal(12,2) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `permissions`
--

CREATE TABLE `permissions` (
  `id` int(10) UNSIGNED NOT NULL,
  `slug` varchar(100) NOT NULL,
  `description` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Déchargement des données de la table `permissions`
--

INSERT INTO `permissions` (`id`, `slug`, `description`) VALUES
(1, 'dashboard.view', 'Accéder au tableau de bord'),
(2, 'etudiants.view', 'Voir les étudiants'),
(3, 'etudiants.create', 'Créer un étudiant'),
(4, 'etudiants.edit', 'Modifier un étudiant'),
(5, 'etudiants.transfer', 'Transférer un étudiant'),
(6, 'etudiants.mes_etudiants', 'Voir ses étudiants'),
(7, 'etudiants.statut_financier', 'Voir le statut financier'),
(8, 'notes.view', 'Voir les notes'),
(9, 'notes.edit', 'Saisir/modifier les notes'),
(10, 'notes.validate', 'Valider les notes'),
(11, 'notes.mes_notes', 'Voir ses propres notes'),
(12, 'notes.soumettre', 'Soumettre les notes'),
(13, 'syllabus.view', 'Voir les programmes'),
(14, 'syllabus.edit', 'Modifier les programmes'),
(15, 'enseignants.view', 'Voir les enseignants'),
(16, 'emploi_temps.view', 'Voir les emplois du temps'),
(17, 'emploi_temps.edit', 'Modifier les emplois du temps'),
(18, 'emploi_temps.mon', 'Voir son emploi du temps'),
(19, 'finances.view', 'Voir les finances'),
(20, 'finances.create', 'Créer une opération financière'),
(21, 'finances.edit', 'Modifier une opération financière'),
(22, 'finances.caisse', 'Accéder à la caisse'),
(23, 'finances.mon_statut', 'Voir son statut financier'),
(24, 'paiements.view', 'Voir les paiements'),
(25, 'paiements.create', 'Créer un paiement'),
(26, 'paiements.validate', 'Valider un paiement'),
(27, 'paiements.imprimer', 'Imprimer un reçu'),
(28, 'bourses.view', 'Voir les bourses'),
(29, 'bourses.edit', 'Modifier les bourses'),
(30, 'documents.view', 'Voir les documents'),
(31, 'documents.archive', 'Archiver des documents'),
(32, 'documents.generer_releve', 'Générer un relevé'),
(33, 'documents.generer_certificat', 'Générer un certificat'),
(34, 'documents.generer_diplome', 'Générer un diplôme'),
(35, 'documents.mon_releve', 'Voir son relevé'),
(36, 'messagerie.view', 'Voir la messagerie'),
(37, 'messagerie.send', 'Envoyer un message'),
(38, 'rapports.view', 'Voir les rapports'),
(39, 'rapports.administratif', 'Rapports administratifs'),
(40, 'rapports.financier', 'Rapports financiers'),
(41, 'rapports.caisse', 'Rapports de caisse'),
(42, 'rapports.academique', 'Rapports académiques'),
(43, 'rapports.departement', 'Rapports de département'),
(44, 'utilisateurs.view', 'Voir les utilisateurs'),
(45, 'utilisateurs.create', 'Créer un utilisateur'),
(46, 'utilisateurs.edit', 'Modifier un utilisateur'),
(47, 'parametres.view', 'Voir les paramètres'),
(48, 'parametres.edit', 'Modifier les paramètres'),
(49, 'bibliotheque.view', 'Voir la bibliothèque'),
(50, 'bibliotheque.preter', 'Prêter un livre'),
(51, 'bibliotheque.retourner', 'Retourner un livre'),
(52, 'ue.view', 'Voir les unités d\'enseignement'),
(53, 'ue.edit', 'Créer/modifier les unités d\'enseignement et les cours'),
(54, 'deliberations.view', 'Voir les délibérations'),
(55, 'deliberations.manage', 'Gérer les jurys et les délibérations'),
(56, 'deliberations.pv', 'Générer les procès-verbaux de délibération'),
(57, 'admissions.view', 'Voir les candidatures'),
(58, 'admissions.manage', 'Traiter les candidatures'),
(59, 'presences.view', 'Voir les présences'),
(60, 'presences.saisir', 'Saisir les présences'),
(61, 'memoires.view', 'Voir les mémoires/TFC'),
(62, 'memoires.manage', 'Gérer les mémoires/TFC et soutenances'),
(63, 'stages.view', 'Voir les stages'),
(64, 'stages.manage', 'Gérer les stages'),
(65, 'reclamations.create', 'Déposer une réclamation de note'),
(66, 'reclamations.traiter', 'Traiter les réclamations de notes'),
(67, 'calendrier.view', 'Voir le calendrier académique'),
(68, 'calendrier.edit', 'Modifier le calendrier académique'),
(69, 'examens.view', 'Voir le planning des examens'),
(70, 'examens.edit', 'Planifier les examens'),
(71, 'cartes.generer', 'Générer les cartes d\'étudiant'),
(72, 'enseignants.edit', 'Modifier les enseignants'),
(73, 'enseignants.heures_valider', 'Valider les heures prestées'),
(74, 'parents.mes_enfants', 'Voir les informations de ses enfants'),
(75, 'journal.view', 'Consulter le journal d\'audit'),
(76, 'roles.manage', 'Gérer les rôles et permissions'),
(77, 'inscriptions.documents.view', 'Voir les pièces des dossiers d\'inscription'),
(78, 'inscriptions.documents.verify', 'Recevoir et vérifier les pièces d\'inscription'),
(79, 'inscriptions.derogation', 'Accorder une dérogation pour dossier incomplet'),
(80, 'documents_requis.manage', 'Gérer la liste des pièces exigées'),
(81, 'bibliotheque.manage', 'Gérer le catalogue et les exemplaires'),
(82, 'bibliotheque.pret', 'Enregistrer prêts, retours et renouvellements'),
(83, 'bibliotheque.amendes', 'Gérer les amendes de bibliothèque'),
(84, 'bibliotheque.reservations', 'Gérer les réservations de livres'),
(85, 'bibliotheque.acquisitions', 'Gérer les acquisitions'),
(86, 'personnel.view', 'Voir le dossier du personnel'),
(87, 'personnel.edit', 'Créer et modifier le dossier du personnel'),
(88, 'personnel.contrats', 'Gérer les contrats'),
(89, 'personnel.sanctions', 'Gérer les sanctions disciplinaires'),
(90, 'personnel.evaluations', 'Gérer les évaluations du personnel'),
(91, 'conges.demander', 'Demander un congé'),
(92, 'conges.approuver', 'Approuver ou refuser les congés'),
(93, 'pointage.view', 'Voir le pointage du personnel'),
(94, 'pointage.edit', 'Saisir le pointage du personnel'),
(95, 'paie.view', 'Consulter la paie'),
(96, 'paie.manage', 'Calculer et valider la paie'),
(97, 'paie.config', 'Paramétrer les règles de paie'),
(98, 'admin_users.view', 'Voir les comptes administrateurs'),
(99, 'admin_users.create', 'Créer un compte administrateur'),
(100, 'admin_users.edit', 'Modifier un compte administrateur'),
(101, 'admin_users.suspend', 'Suspendre / réactiver un administrateur'),
(102, 'admin_users.promote', 'Changer le rôle admin ↔ super_admin'),
(103, 'admin_logs.view', 'Consulter le journal des actions administrateur');

-- --------------------------------------------------------

--
-- Structure de la table `programs`
--

CREATE TABLE `programs` (
  `id` int(10) UNSIGNED NOT NULL,
  `code` varchar(20) NOT NULL,
  `name` varchar(150) NOT NULL,
  `department_id` int(10) UNSIGNED NOT NULL,
  `level` enum('L1','L2','L3','M1','M2','D') NOT NULL,
  `duration_years` tinyint(3) UNSIGNED NOT NULL DEFAULT 3,
  `is_active` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `roles`
--

CREATE TABLE `roles` (
  `id` int(10) UNSIGNED NOT NULL,
  `slug` varchar(50) NOT NULL,
  `label` varchar(100) NOT NULL,
  `level` smallint(6) NOT NULL DEFAULT 10,
  `is_system` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Déchargement des données de la table `roles`
--

INSERT INTO `roles` (`id`, `slug`, `label`, `level`, `is_system`) VALUES
(1, 'super_admin', 'Super Administrateur', 100, 1),
(2, 'secretaire_general', 'Secrétaire Général', 80, 0),
(3, 'daf', 'Directeur Administratif et Financier', 75, 0),
(4, 'chef_departement', 'Chef de Département', 65, 0),
(5, 'comptable', 'Comptable', 60, 0),
(6, 'assurance_qualite', 'Responsable Assurance Qualité', 60, 0),
(7, 'recherche_innovation', 'Directeur Recherche & Innovation', 60, 0),
(8, 'lecteur', 'Lecteur / Bibliothécaire', 50, 0),
(9, 'parent', 'Parent', 15, 0),
(10, 'etudiant', 'Étudiant', 10, 0),
(11, 'recteur', 'Recteur / Vice-recteur', 90, 0),
(12, 'directeur_campus', 'Directeur de Campus', 78, 0),
(13, 'doyen', 'Doyen de Faculté', 70, 0),
(14, 'agent_scolarite', 'Agent de Scolarité', 55, 0),
(15, 'caissier', 'Caissier', 55, 0),
(16, 'enseignant', 'Enseignant', 40, 0),
(17, 'drh', 'Responsable des Ressources Humaines', 65, 0),
(18, 'system_admin', 'Administrateur Système (interne, non connectable)', 100, 1);

-- --------------------------------------------------------

--
-- Structure de la table `role_permissions`
--

CREATE TABLE `role_permissions` (
  `role_id` int(10) UNSIGNED NOT NULL,
  `permission_id` int(10) UNSIGNED NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Déchargement des données de la table `role_permissions`
--

INSERT INTO `role_permissions` (`role_id`, `permission_id`) VALUES
(1, 1),
(1, 2),
(1, 3),
(1, 4),
(1, 5),
(1, 6),
(1, 7),
(1, 8),
(1, 9),
(1, 10),
(1, 11),
(1, 12),
(1, 13),
(1, 14),
(1, 15),
(1, 16),
(1, 17),
(1, 18),
(1, 19),
(1, 20),
(1, 21),
(1, 22),
(1, 23),
(1, 24),
(1, 25),
(1, 26),
(1, 27),
(1, 28),
(1, 29),
(1, 30),
(1, 31),
(1, 32),
(1, 33),
(1, 34),
(1, 35),
(1, 36),
(1, 37),
(1, 38),
(1, 39),
(1, 40),
(1, 41),
(1, 42),
(1, 43),
(1, 44),
(1, 45),
(1, 46),
(1, 47),
(1, 48),
(1, 49),
(1, 50),
(1, 51),
(1, 52),
(1, 53),
(1, 54),
(1, 55),
(1, 56),
(1, 57),
(1, 58),
(1, 59),
(1, 60),
(1, 61),
(1, 62),
(1, 63),
(1, 64),
(1, 65),
(1, 66),
(1, 67),
(1, 68),
(1, 69),
(1, 70),
(1, 71),
(1, 72),
(1, 73),
(1, 74),
(1, 75),
(1, 76),
(1, 77),
(1, 78),
(1, 79),
(1, 80),
(1, 81),
(1, 82),
(1, 83),
(1, 84),
(1, 85),
(1, 86),
(1, 87),
(1, 88),
(1, 89),
(1, 90),
(1, 91),
(1, 92),
(1, 93),
(1, 94),
(1, 95),
(1, 96),
(1, 97),
(1, 98),
(1, 99),
(1, 100),
(1, 101),
(1, 102),
(1, 103),
(2, 1),
(2, 2),
(2, 3),
(2, 4),
(2, 5),
(2, 6),
(2, 7),
(2, 8),
(2, 9),
(2, 10),
(2, 11),
(2, 12),
(2, 13),
(2, 14),
(2, 15),
(2, 16),
(2, 17),
(2, 18),
(2, 19),
(2, 23),
(2, 24),
(2, 27),
(2, 28),
(2, 29),
(2, 30),
(2, 31),
(2, 32),
(2, 33),
(2, 34),
(2, 35),
(2, 36),
(2, 37),
(2, 38),
(2, 39),
(2, 40),
(2, 41),
(2, 42),
(2, 43),
(2, 44),
(2, 45),
(2, 46),
(2, 47),
(2, 49),
(2, 50),
(2, 51),
(2, 52),
(2, 53),
(2, 54),
(2, 55),
(2, 56),
(2, 57),
(2, 58),
(2, 59),
(2, 60),
(2, 61),
(2, 62),
(2, 63),
(2, 64),
(2, 65),
(2, 66),
(2, 67),
(2, 68),
(2, 69),
(2, 70),
(2, 71),
(2, 72),
(2, 73),
(2, 74),
(2, 75),
(2, 77),
(2, 78),
(2, 79),
(2, 80),
(2, 86),
(2, 90),
(2, 91),
(2, 92),
(2, 93),
(3, 1),
(3, 2),
(3, 7),
(3, 15),
(3, 19),
(3, 20),
(3, 21),
(3, 22),
(3, 23),
(3, 24),
(3, 25),
(3, 26),
(3, 27),
(3, 28),
(3, 29),
(3, 30),
(3, 36),
(3, 37),
(3, 38),
(3, 39),
(3, 40),
(3, 41),
(3, 44),
(3, 67),
(3, 73),
(3, 86),
(3, 88),
(3, 91),
(3, 95),
(3, 96),
(3, 97),
(4, 1),
(4, 2),
(4, 8),
(4, 10),
(4, 13),
(4, 14),
(4, 15),
(4, 16),
(4, 17),
(4, 36),
(4, 37),
(4, 38),
(4, 42),
(4, 43),
(4, 49),
(4, 52),
(4, 53),
(4, 54),
(4, 59),
(4, 61),
(4, 62),
(4, 63),
(4, 64),
(4, 66),
(4, 67),
(4, 69),
(4, 70),
(4, 73),
(4, 86),
(4, 90),
(4, 91),
(4, 92),
(4, 93),
(5, 1),
(5, 2),
(5, 7),
(5, 19),
(5, 20),
(5, 21),
(5, 22),
(5, 24),
(5, 25),
(5, 26),
(5, 27),
(5, 28),
(5, 30),
(5, 36),
(5, 37),
(5, 38),
(5, 40),
(5, 41),
(5, 91),
(5, 95),
(6, 1),
(6, 2),
(6, 8),
(6, 13),
(6, 15),
(6, 16),
(6, 19),
(6, 24),
(6, 28),
(6, 30),
(6, 36),
(6, 37),
(6, 38),
(6, 39),
(6, 40),
(6, 41),
(6, 42),
(6, 43),
(6, 49),
(6, 52),
(6, 54),
(6, 57),
(6, 59),
(6, 61),
(6, 63),
(6, 67),
(6, 69),
(6, 75),
(6, 77),
(6, 86),
(6, 91),
(6, 93),
(7, 1),
(7, 15),
(7, 36),
(7, 37),
(7, 38),
(7, 42),
(7, 49),
(7, 61),
(7, 62),
(7, 91),
(8, 1),
(8, 2),
(8, 36),
(8, 37),
(8, 49),
(8, 50),
(8, 51),
(8, 81),
(8, 82),
(8, 83),
(8, 84),
(8, 85),
(8, 91),
(9, 1),
(9, 11),
(9, 23),
(9, 36),
(9, 37),
(9, 67),
(9, 74),
(10, 1),
(10, 11),
(10, 13),
(10, 18),
(10, 23),
(10, 35),
(10, 36),
(10, 37),
(10, 49),
(10, 65),
(10, 67),
(10, 69),
(11, 1),
(11, 2),
(11, 8),
(11, 13),
(11, 15),
(11, 16),
(11, 19),
(11, 24),
(11, 28),
(11, 30),
(11, 36),
(11, 37),
(11, 38),
(11, 39),
(11, 40),
(11, 41),
(11, 42),
(11, 43),
(11, 44),
(11, 47),
(11, 49),
(11, 52),
(11, 54),
(11, 57),
(11, 59),
(11, 61),
(11, 63),
(11, 67),
(11, 69),
(11, 75),
(11, 86),
(11, 90),
(11, 91),
(11, 92),
(11, 93),
(12, 1),
(12, 2),
(12, 3),
(12, 4),
(12, 5),
(12, 8),
(12, 13),
(12, 15),
(12, 16),
(12, 17),
(12, 19),
(12, 24),
(12, 28),
(12, 30),
(12, 36),
(12, 37),
(12, 38),
(12, 39),
(12, 42),
(12, 44),
(12, 47),
(12, 49),
(12, 52),
(12, 54),
(12, 57),
(12, 58),
(12, 59),
(12, 61),
(12, 63),
(12, 67),
(12, 68),
(12, 69),
(12, 70),
(12, 75),
(12, 77),
(12, 78),
(12, 79),
(12, 80),
(12, 86),
(12, 90),
(12, 91),
(12, 92),
(12, 93),
(13, 1),
(13, 2),
(13, 8),
(13, 10),
(13, 13),
(13, 14),
(13, 15),
(13, 16),
(13, 19),
(13, 24),
(13, 28),
(13, 30),
(13, 36),
(13, 37),
(13, 38),
(13, 42),
(13, 43),
(13, 44),
(13, 47),
(13, 49),
(13, 52),
(13, 53),
(13, 54),
(13, 55),
(13, 56),
(13, 57),
(13, 59),
(13, 61),
(13, 62),
(13, 63),
(13, 64),
(13, 66),
(13, 67),
(13, 69),
(13, 70),
(13, 75),
(13, 86),
(13, 90),
(13, 91),
(13, 92),
(13, 93),
(14, 1),
(14, 2),
(14, 3),
(14, 4),
(14, 5),
(14, 8),
(14, 13),
(14, 16),
(14, 30),
(14, 32),
(14, 33),
(14, 35),
(14, 36),
(14, 37),
(14, 52),
(14, 57),
(14, 58),
(14, 67),
(14, 69),
(14, 71),
(14, 77),
(14, 78),
(14, 91),
(15, 1),
(15, 2),
(15, 7),
(15, 22),
(15, 24),
(15, 25),
(15, 27),
(15, 41),
(15, 91),
(16, 1),
(16, 6),
(16, 8),
(16, 9),
(16, 12),
(16, 13),
(16, 14),
(16, 18),
(16, 36),
(16, 37),
(16, 49),
(16, 52),
(16, 59),
(16, 60),
(16, 61),
(16, 63),
(16, 66),
(16, 67),
(16, 69),
(16, 91),
(17, 1),
(17, 15),
(17, 30),
(17, 36),
(17, 37),
(17, 38),
(17, 39),
(17, 67),
(17, 72),
(17, 73),
(17, 86),
(17, 87),
(17, 88),
(17, 89),
(17, 90),
(17, 91),
(17, 92),
(17, 93),
(17, 94),
(17, 95);

-- --------------------------------------------------------

--
-- Structure de la table `rooms`
--

CREATE TABLE `rooms` (
  `id` int(10) UNSIGNED NOT NULL,
  `campus_id` int(10) UNSIGNED NOT NULL,
  `code` varchar(30) NOT NULL,
  `name` varchar(100) DEFAULT NULL,
  `capacity` smallint(5) UNSIGNED DEFAULT 0,
  `type` enum('amphi','salle','labo','salle_info','autre') DEFAULT 'salle',
  `is_active` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `scholarships`
--

CREATE TABLE `scholarships` (
  `id` int(10) UNSIGNED NOT NULL,
  `student_id` int(10) UNSIGNED NOT NULL,
  `academic_year_id` int(10) UNSIGNED NOT NULL,
  `type` enum('bourse_entière','bourse_partielle','exonération','aide_sociale','bourse_état','bourse_externe') NOT NULL,
  `percentage` decimal(5,2) DEFAULT 100.00,
  `amount` decimal(12,2) DEFAULT 0.00,
  `reason` varchar(255) DEFAULT NULL,
  `provider` varchar(150) DEFAULT NULL,
  `status` enum('en_attente','approuvée','refusée','active','expirée') NOT NULL DEFAULT 'en_attente',
  `approved_by` int(10) UNSIGNED DEFAULT NULL,
  `approved_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ;

-- --------------------------------------------------------

--
-- Structure de la table `semesters`
--

CREATE TABLE `semesters` (
  `id` int(10) UNSIGNED NOT NULL,
  `academic_year_id` int(10) UNSIGNED NOT NULL,
  `label` varchar(50) NOT NULL,
  `rank_no` tinyint(3) UNSIGNED DEFAULT NULL,
  `start_date` date NOT NULL,
  `end_date` date NOT NULL,
  `is_closed` tinyint(1) NOT NULL DEFAULT 0
) ;

--
-- Déchargement des données de la table `semesters`
--

INSERT INTO `semesters` (`id`, `academic_year_id`, `label`, `rank_no`, `start_date`, `end_date`, `is_closed`) VALUES
(1, 1, 'Semestre 1', 1, '2026-09-01', '2027-01-31', 0),
(2, 1, 'Semestre 2', 2, '2027-02-01', '2027-06-30', 0);

-- --------------------------------------------------------

--
-- Structure de la table `semester_results`
--

CREATE TABLE `semester_results` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `student_id` int(10) UNSIGNED NOT NULL,
  `academic_year_id` int(10) UNSIGNED NOT NULL,
  `semester_rank` tinyint(3) UNSIGNED NOT NULL,
  `session_no` tinyint(3) UNSIGNED NOT NULL DEFAULT 1,
  `average` decimal(5,2) DEFAULT NULL,
  `credits_total` smallint(5) UNSIGNED NOT NULL DEFAULT 0,
  `credits_earned` smallint(5) UNSIGNED NOT NULL DEFAULT 0,
  `status` enum('validé','rattrapage','ajourné') NOT NULL,
  `is_compensated` tinyint(1) NOT NULL DEFAULT 0,
  `computed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `sequences`
--

CREATE TABLE `sequences` (
  `name` varchar(50) NOT NULL,
  `current_value` bigint(20) UNSIGNED NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `services`
--

CREATE TABLE `services` (
  `id` int(10) UNSIGNED NOT NULL,
  `code` varchar(20) NOT NULL,
  `name` varchar(150) NOT NULL,
  `campus_id` int(10) UNSIGNED DEFAULT NULL,
  `head_id` int(10) UNSIGNED DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Déchargement des données de la table `services`
--

INSERT INTO `services` (`id`, `code`, `name`, `campus_id`, `head_id`, `is_active`) VALUES
(1, 'SCOLARITE', 'Service de la Scolarité', NULL, NULL, 1),
(2, 'FINANCE', 'Service Financier et Comptabilité', NULL, NULL, 1),
(3, 'RH', 'Ressources Humaines', NULL, NULL, 1),
(4, 'BIBLIO', 'Bibliothèque', NULL, NULL, 1),
(5, 'INFO', 'Service Informatique', NULL, NULL, 1),
(6, 'LOGISTIQUE', 'Logistique et Entretien', NULL, NULL, 1),
(7, 'SECURITE', 'Sécurité', NULL, NULL, 1),
(8, 'QUALITE', 'Assurance Qualité', NULL, NULL, 1),
(9, 'RECHERCHE', 'Recherche et Innovation', NULL, NULL, 1);

-- --------------------------------------------------------

--
-- Structure de la table `settings`
--

CREATE TABLE `settings` (
  `id` int(10) UNSIGNED NOT NULL,
  `key_name` varchar(100) NOT NULL,
  `value` text DEFAULT NULL,
  `type` enum('string','int','bool','json') NOT NULL DEFAULT 'string',
  `description` varchar(255) DEFAULT NULL,
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Déchargement des données de la table `settings`
--

INSERT INTO `settings` (`id`, `key_name`, `value`, `type`, `description`, `updated_at`) VALUES
(1, 'institution_name', 'EALI', 'string', 'Nom de l\'institution', '2026-10-20 16:13:27'),
(2, 'institution_motto', 'Empowering Minds, Building Futures', 'string', 'Devise de l\'institution', '2026-10-20 16:13:27'),
(3, 'default_currency', 'BIF', 'string', 'Devise par défaut', '2026-10-20 16:13:27'),
(4, 'pass_mark', '10', 'int', 'Note minimale de validation', '2026-10-20 16:13:27'),
(5, 'max_score', '20', 'int', 'Note maximale', '2026-10-20 16:13:27'),
(6, 'vat_rate', '18', 'int', 'Taux de TVA (%)', '2026-10-20 16:13:27'),
(7, 'academic_system', 'LMD', 'string', 'Système académique', '2026-10-20 16:13:27'),
(8, 'country', 'Burundi', 'string', 'Pays', '2026-10-23 13:34:35'),
(9, 'timezone', 'Africa/Bujumbura', 'string', 'Fuseau horaire', '2026-10-23 13:34:35'),
(10, 'credits_per_semester', '30', 'int', 'Crédits par semestre (norme LMD)', '2026-10-23 13:34:35'),
(11, 'credits_per_year', '60', 'int', 'Crédits par année', '2026-10-23 13:34:35'),
(12, 'credits_licence', '180', 'int', 'Crédits pour valider un cycle Licence/Bachelier', '2026-10-23 13:34:35'),
(13, 'credits_master', '120', 'int', 'Crédits pour valider un Master', '2026-10-23 13:34:35'),
(14, 'min_credits_to_advance', '45', 'int', 'Crédits minimum pour passer au niveau supérieur avec dettes', '2026-10-23 13:34:35'),
(15, 'semester_compensation_enabled', '1', 'bool', 'Compensation entre UE d\'un même semestre', '2026-10-23 13:34:35'),
(16, 'min_attendance_rate', '75', 'int', 'Taux minimal de présence (%)', '2026-10-23 13:34:35'),
(17, 'max_second_session', '1', 'int', 'Nombre de sessions de rattrapage par année', '2026-10-23 13:34:35'),
(18, 'enforce_enrollment_documents', '1', 'bool', 'Interdire validation inscription si dossier incomplet (sauf dérogation)', '2026-10-23 13:34:35');

-- --------------------------------------------------------

--
-- Structure de la table `staff_appraisals`
--

CREATE TABLE `staff_appraisals` (
  `id` int(10) UNSIGNED NOT NULL,
  `user_id` int(10) UNSIGNED NOT NULL,
  `academic_year_id` int(10) UNSIGNED NOT NULL,
  `evaluator_id` int(10) UNSIGNED DEFAULT NULL,
  `score` decimal(5,2) DEFAULT NULL,
  `strengths` text DEFAULT NULL,
  `improvements` text DEFAULT NULL,
  `decision` enum('maintien','promotion','formation','avertissement') DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ;

-- --------------------------------------------------------

--
-- Structure de la table `staff_attendance`
--

CREATE TABLE `staff_attendance` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `user_id` int(10) UNSIGNED NOT NULL,
  `work_date` date NOT NULL,
  `check_in` time DEFAULT NULL,
  `check_out` time DEFAULT NULL,
  `status` enum('présent','absent','retard','congé','mission','férié') NOT NULL DEFAULT 'présent',
  `justification` varchar(255) DEFAULT NULL,
  `recorded_by` int(10) UNSIGNED DEFAULT NULL
) ;

-- --------------------------------------------------------

--
-- Structure de la table `staff_contracts`
--

CREATE TABLE `staff_contracts` (
  `id` int(10) UNSIGNED NOT NULL,
  `user_id` int(10) UNSIGNED NOT NULL,
  `contract_type` enum('CDI','CDD','vacation','stage','mission') NOT NULL,
  `start_date` date NOT NULL,
  `end_date` date DEFAULT NULL,
  `base_salary` decimal(12,2) NOT NULL DEFAULT 0.00,
  `currency` char(3) NOT NULL DEFAULT 'BIF',
  `status` enum('actif','terminé','résilié','suspendu') NOT NULL DEFAULT 'actif',
  `document_id` bigint(20) UNSIGNED DEFAULT NULL,
  `notes` varchar(255) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ;

-- --------------------------------------------------------

--
-- Structure de la table `staff_documents`
--

CREATE TABLE `staff_documents` (
  `id` int(10) UNSIGNED NOT NULL,
  `user_id` int(10) UNSIGNED NOT NULL,
  `type` enum('cv','diplôme','contrat','cni','casier_judiciaire','attestation','autre') NOT NULL,
  `title` varchar(200) NOT NULL,
  `file_path` varchar(255) DEFAULT NULL,
  `document_id` bigint(20) UNSIGNED DEFAULT NULL,
  `expires_at` date DEFAULT NULL,
  `uploaded_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `staff_profiles`
--

CREATE TABLE `staff_profiles` (
  `user_id` int(10) UNSIGNED NOT NULL,
  `employee_no` varchar(30) DEFAULT NULL,
  `staff_category` enum('enseignant','administratif','technique','appui','direction') NOT NULL,
  `job_title_id` int(10) UNSIGNED DEFAULT NULL,
  `service_id` int(10) UNSIGNED DEFAULT NULL,
  `department_id` int(10) UNSIGNED DEFAULT NULL,
  `campus_id` int(10) UNSIGNED DEFAULT NULL,
  `hire_date` date DEFAULT NULL,
  `employment_status` enum('actif','en_congé','suspendu','retraité','démissionné','licencié','décédé') NOT NULL DEFAULT 'actif',
  `end_date` date DEFAULT NULL,
  `national_id` varchar(30) DEFAULT NULL,
  `birth_place` varchar(150) DEFAULT NULL,
  `marital_status` enum('célibataire','marié','divorcé','veuf') DEFAULT NULL,
  `dependents_count` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `inss_number` varchar(30) DEFAULT NULL,
  `bank_name` varchar(100) DEFAULT NULL,
  `bank_account` varchar(50) DEFAULT NULL,
  `province_origin` varchar(100) DEFAULT NULL,
  `commune_origin` varchar(100) DEFAULT NULL,
  `address` varchar(255) DEFAULT NULL,
  `emergency_contact_name` varchar(150) DEFAULT NULL,
  `emergency_contact_phone` varchar(30) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `staff_sanctions`
--

CREATE TABLE `staff_sanctions` (
  `id` int(10) UNSIGNED NOT NULL,
  `user_id` int(10) UNSIGNED NOT NULL,
  `type` enum('avertissement','blâme','mise_à_pied','révocation') NOT NULL,
  `reason` text NOT NULL,
  `sanction_date` date NOT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `decided_by` int(10) UNSIGNED DEFAULT NULL,
  `document_id` bigint(20) UNSIGNED DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `staff_trainings`
--

CREATE TABLE `staff_trainings` (
  `id` int(10) UNSIGNED NOT NULL,
  `user_id` int(10) UNSIGNED NOT NULL,
  `title` varchar(200) NOT NULL,
  `organizer` varchar(150) DEFAULT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `certificate_document_id` bigint(20) UNSIGNED DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `students`
--

CREATE TABLE `students` (
  `id` int(10) UNSIGNED NOT NULL,
  `user_id` int(10) UNSIGNED DEFAULT NULL,
  `matricule` varchar(30) NOT NULL,
  `first_name` varchar(100) NOT NULL,
  `last_name` varchar(100) NOT NULL,
  `gender` enum('M','F','O') DEFAULT 'O',
  `birth_date` date DEFAULT NULL,
  `birth_place` varchar(150) DEFAULT NULL,
  `nationality` varchar(80) DEFAULT 'Burundaise',
  `national_id` varchar(30) DEFAULT NULL,
  `address` varchar(255) DEFAULT NULL,
  `province_origin` varchar(100) DEFAULT NULL,
  `commune_origin` varchar(100) DEFAULT NULL,
  `colline_origin` varchar(100) DEFAULT NULL,
  `secondary_school` varchar(150) DEFAULT NULL,
  `secondary_diploma_year` smallint(5) UNSIGNED DEFAULT NULL,
  `secondary_diploma_percentage` decimal(5,2) DEFAULT NULL,
  `entry_academic_year_id` int(10) UNSIGNED DEFAULT NULL,
  `admission_id` int(10) UNSIGNED DEFAULT NULL,
  `phone` varchar(30) DEFAULT NULL,
  `email` varchar(150) DEFAULT NULL,
  `guardian_name` varchar(150) DEFAULT NULL,
  `guardian_phone` varchar(30) DEFAULT NULL,
  `campus_id` int(10) UNSIGNED DEFAULT NULL,
  `program_id` int(10) UNSIGNED DEFAULT NULL,
  `current_level` enum('L1','L2','L3','M1','M2','D') DEFAULT 'L1',
  `status` enum('actif','suspendu','diplômé','abandon','transféré') NOT NULL DEFAULT 'actif',
  `photo` varchar(255) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ;

-- --------------------------------------------------------

--
-- Structure de la table `student_cards`
--

CREATE TABLE `student_cards` (
  `id` int(10) UNSIGNED NOT NULL,
  `student_id` int(10) UNSIGNED NOT NULL,
  `academic_year_id` int(10) UNSIGNED NOT NULL,
  `card_number` varchar(30) NOT NULL,
  `issued_at` datetime NOT NULL DEFAULT current_timestamp(),
  `expires_at` date DEFAULT NULL,
  `status` enum('active','perdue','expirée','annulée') NOT NULL DEFAULT 'active',
  `issued_by` int(10) UNSIGNED DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `student_transfers`
--

CREATE TABLE `student_transfers` (
  `id` int(10) UNSIGNED NOT NULL,
  `student_id` int(10) UNSIGNED NOT NULL,
  `from_campus_id` int(10) UNSIGNED NOT NULL,
  `to_campus_id` int(10) UNSIGNED NOT NULL,
  `from_program_id` int(10) UNSIGNED DEFAULT NULL,
  `to_program_id` int(10) UNSIGNED DEFAULT NULL,
  `reason` text DEFAULT NULL,
  `status` enum('en_attente','approuvé_source','approuvé_destination','refusé','effectué') NOT NULL DEFAULT 'en_attente',
  `requested_at` datetime NOT NULL DEFAULT current_timestamp(),
  `approved_source_at` datetime DEFAULT NULL,
  `approved_dest_at` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `syllabus`
--

CREATE TABLE `syllabus` (
  `id` int(10) UNSIGNED NOT NULL,
  `course_id` int(10) UNSIGNED NOT NULL,
  `chapter_number` smallint(5) UNSIGNED NOT NULL,
  `title` varchar(200) NOT NULL,
  `description` text DEFAULT NULL,
  `planned_hours` smallint(5) UNSIGNED DEFAULT 0,
  `covered_hours` smallint(5) UNSIGNED DEFAULT 0,
  `is_covered` tinyint(1) NOT NULL DEFAULT 0,
  `covered_at` datetime DEFAULT NULL,
  `updated_by` int(10) UNSIGNED DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `teacher_profiles`
--

CREATE TABLE `teacher_profiles` (
  `user_id` int(10) UNSIGNED NOT NULL,
  `academic_rank` enum('assistant','chargé_de_cours','professeur_associé','professeur','professeur_ordinaire') NOT NULL DEFAULT 'assistant',
  `highest_degree` enum('licence','master','doctorat','autre') DEFAULT NULL,
  `specialty` varchar(150) DEFAULT NULL,
  `contract_type` enum('permanent','vacataire','visiteur') NOT NULL DEFAULT 'permanent',
  `department_id` int(10) UNSIGNED DEFAULT NULL,
  `hourly_rate` decimal(12,2) NOT NULL DEFAULT 0.00,
  `currency` char(3) NOT NULL DEFAULT 'BIF',
  `hire_date` date DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `teaching_units`
--

CREATE TABLE `teaching_units` (
  `id` int(10) UNSIGNED NOT NULL,
  `code` varchar(20) NOT NULL,
  `title` varchar(200) NOT NULL,
  `program_id` int(10) UNSIGNED NOT NULL,
  `level` enum('L1','L2','L3','M1','M2','D') NOT NULL,
  `semester_rank` tinyint(3) UNSIGNED NOT NULL DEFAULT 1,
  `category` enum('fondamentale','méthodologique','découverte','transversale','optionnelle','libre') NOT NULL DEFAULT 'fondamentale',
  `is_mandatory` tinyint(1) NOT NULL DEFAULT 1,
  `pass_mark` decimal(4,2) NOT NULL DEFAULT 10.00,
  `compensation` enum('interne','aucune') NOT NULL DEFAULT 'interne',
  `min_course_score` decimal(4,2) NOT NULL DEFAULT 0.00,
  `capitalize_courses` tinyint(1) NOT NULL DEFAULT 1,
  `compensable_semester` tinyint(1) NOT NULL DEFAULT 1,
  `description` text DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ;

-- --------------------------------------------------------

--
-- Structure de la table `theses`
--

CREATE TABLE `theses` (
  `id` int(10) UNSIGNED NOT NULL,
  `student_id` int(10) UNSIGNED NOT NULL,
  `academic_year_id` int(10) UNSIGNED NOT NULL,
  `type` enum('TFC','mémoire','thèse') NOT NULL DEFAULT 'mémoire',
  `title` varchar(300) NOT NULL,
  `supervisor_id` int(10) UNSIGNED DEFAULT NULL,
  `co_supervisor_id` int(10) UNSIGNED DEFAULT NULL,
  `status` enum('proposé','validé','en_cours','déposé','soutenu','refusé') NOT NULL DEFAULT 'proposé',
  `deposit_date` date DEFAULT NULL,
  `defense_date` datetime DEFAULT NULL,
  `defense_room_id` int(10) UNSIGNED DEFAULT NULL,
  `score` decimal(5,2) DEFAULT NULL,
  `credits` tinyint(3) UNSIGNED DEFAULT NULL,
  `mention_label` varchar(80) DEFAULT NULL,
  `document_id` bigint(20) UNSIGNED DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ;

-- --------------------------------------------------------

--
-- Structure de la table `thesis_jury_members`
--

CREATE TABLE `thesis_jury_members` (
  `thesis_id` int(10) UNSIGNED NOT NULL,
  `user_id` int(10) UNSIGNED NOT NULL,
  `role` enum('président','rapporteur','examinateur','secrétaire') NOT NULL DEFAULT 'examinateur'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la table `timetables`
--

CREATE TABLE `timetables` (
  `id` int(10) UNSIGNED NOT NULL,
  `course_id` int(10) UNSIGNED NOT NULL,
  `teacher_id` int(10) UNSIGNED NOT NULL,
  `room_id` int(10) UNSIGNED NOT NULL,
  `campus_id` int(10) UNSIGNED NOT NULL,
  `semester_id` int(10) UNSIGNED NOT NULL,
  `day_of_week` tinyint(3) UNSIGNED NOT NULL,
  `start_time` time NOT NULL,
  `end_time` time NOT NULL,
  `type` enum('CM','TD','TP') NOT NULL DEFAULT 'CM',
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ;

--
-- Déclencheurs `timetables`
--
DELIMITER $$
CREATE TRIGGER `trg_timetables_bi` BEFORE INSERT ON `timetables` FOR EACH ROW BEGIN
  IF EXISTS (SELECT 1 FROM `timetables` t
              WHERE t.`semester_id`=NEW.`semester_id` AND t.`day_of_week`=NEW.`day_of_week`
                AND t.`start_time`<NEW.`end_time` AND t.`end_time`>NEW.`start_time`
                AND (t.`room_id`=NEW.`room_id` OR t.`teacher_id`=NEW.`teacher_id`)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Conflit d''emploi du temps : salle ou enseignant déjà occupé';
  END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_timetables_bu` BEFORE UPDATE ON `timetables` FOR EACH ROW BEGIN
  IF EXISTS (SELECT 1 FROM `timetables` t
              WHERE t.`id`<>OLD.`id` AND t.`semester_id`=NEW.`semester_id` AND t.`day_of_week`=NEW.`day_of_week`
                AND t.`start_time`<NEW.`end_time` AND t.`end_time`>NEW.`start_time`
                AND (t.`room_id`=NEW.`room_id` OR t.`teacher_id`=NEW.`teacher_id`)) THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Conflit d''emploi du temps : salle ou enseignant déjà occupé';
  END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Structure de la table `unit_results`
--

CREATE TABLE `unit_results` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `student_id` int(10) UNSIGNED NOT NULL,
  `unit_id` int(10) UNSIGNED NOT NULL,
  `academic_year_id` int(10) UNSIGNED NOT NULL,
  `session_no` tinyint(3) UNSIGNED NOT NULL DEFAULT 1,
  `average` decimal(5,2) DEFAULT NULL,
  `credits_total` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `credits_earned` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `status` enum('validé','rattrapage','ajourné') NOT NULL,
  `compensation_level` enum('aucune','ue','semestre') NOT NULL DEFAULT 'aucune',
  `computed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ;

-- --------------------------------------------------------

--
-- Structure de la table `users`
--

CREATE TABLE `users` (
  `id` int(10) UNSIGNED NOT NULL,
  `uuid` char(36) NOT NULL,
  `user_name` varchar(100) NOT NULL,
  `email` varchar(150) NOT NULL,
  `phone` varchar(30) DEFAULT NULL,
  `password_hash` varchar(255) NOT NULL,
  `f_name` varchar(100) NOT NULL,
  `l_name` varchar(100) NOT NULL,
  `gender` enum('M','F','O') DEFAULT 'O',
  `birth_date` date DEFAULT NULL,
  `category` varchar(50) NOT NULL,
  `role_id` int(10) UNSIGNED DEFAULT NULL,
  `campus_id` int(10) UNSIGNED DEFAULT NULL,
  `status` enum('actif','désactivé','suspendu') NOT NULL DEFAULT 'actif',
  `must_change_password` tinyint(1) NOT NULL DEFAULT 0,
  `failed_attempts` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `locked_until` datetime DEFAULT NULL,
  `password_changed_at` datetime DEFAULT NULL,
  `profil` varchar(255) DEFAULT NULL,
  `email_verified_at` datetime DEFAULT NULL,
  `last_login_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Déchargement des données de la table `users`
--

INSERT INTO `users` (`id`, `uuid`, `user_name`, `email`, `phone`, `password_hash`, `f_name`, `l_name`, `gender`, `birth_date`, `category`, `role_id`, `campus_id`, `status`, `must_change_password`, `failed_attempts`, `locked_until`, `password_changed_at`, `profil`, `email_verified_at`, `last_login_at`, `created_at`, `updated_at`) VALUES
(1, 'a493ccbc-cc92-11f1-bdf4-4c327596066b', 'superadmin', 'superadmin@uia.edu.bi', '+257 79 000 000', '$2y$10$e0MYzXyjpJS7Pd0RVvHwHe1K7l0w7Z0h1f8D9oQ8vB1wZ9kQmQ9eO', 'Super', 'Administrateur', 'M', NULL, 'system_admin', 18, NULL, 'actif', 1, 0, NULL, NULL, NULL, NULL, NULL, '2026-10-20 16:29:22', '2026-10-23 13:34:36'),
(2, 'd2e4a9a6-cc92-11f1-bdf4-4c327596066b', 'sg.test', 'sg@uia.edu.bi', '+257 79 100 001', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Alice', 'Ndayishimiye', 'F', NULL, 'secretaire_general', 2, NULL, 'actif', 1, 0, NULL, NULL, NULL, NULL, NULL, '2026-10-20 16:30:40', '2026-10-23 13:34:35'),
(3, 'd2e72c08-cc92-11f1-bdf4-4c327596066b', 'daf.test', 'daf@uia.edu.bi', '+257 79 100 002', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Jean', 'Nkurunziza', 'M', NULL, 'daf', 3, NULL, 'actif', 1, 0, NULL, NULL, NULL, NULL, NULL, '2026-10-20 16:30:40', '2026-10-23 13:34:35'),
(4, 'd2e86da2-cc92-11f1-bdf4-4c327596066b', 'comptable.test', 'comptable@uia.edu.bi', '+257 79 100 003', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Marie', 'Uwimana', 'F', NULL, 'comptable', 5, NULL, 'actif', 1, 0, NULL, NULL, NULL, NULL, NULL, '2026-10-20 16:30:40', '2026-10-23 13:34:35'),
(5, 'd2e9ed8a-cc92-11f1-bdf4-4c327596066b', 'lecteur.test', 'lecteur@uia.edu.bi', '+257 79 100 004', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Paul', 'Habimana', 'M', NULL, 'lecteur', 8, NULL, 'actif', 1, 0, NULL, NULL, NULL, NULL, NULL, '2026-10-20 16:30:40', '2026-10-23 13:34:35'),
(6, 'd2ebb9ee-cc92-11f1-bdf4-4c327596066b', 'chef.test', 'chef@uia.edu.bi', '+257 79 100 005', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Pierre', 'Bizimana', 'M', NULL, 'chef_departement', 4, 2, 'actif', 1, 0, NULL, NULL, NULL, NULL, NULL, '2026-10-20 16:30:40', '2026-10-23 13:34:35'),
(7, 'd2edc450-cc92-11f1-bdf4-4c327596066b', 'aq.test', 'aq@uia.edu.bi', '+257 79 100 006', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Claudine', 'Ntakirutimana', 'F', NULL, 'assurance_qualite', 6, 3, 'actif', 1, 0, NULL, NULL, NULL, NULL, NULL, '2026-10-20 16:30:40', '2026-10-23 13:34:35'),
(8, 'd2efc49e-cc92-11f1-bdf4-4c327596066b', 'recherche.test', 'recherche@uia.edu.bi', '+257 79 100 007', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Éric', 'Ndayizeye', 'M', NULL, 'recherche_innovation', 7, NULL, 'actif', 1, 0, NULL, NULL, NULL, NULL, NULL, '2026-10-20 16:30:40', '2026-10-23 13:34:35'),
(9, 'd2f1b7e0-cc92-11f1-bdf4-4c327596066b', 'etudiant.test', 'etudiant@uia.edu.bi', '+257 79 100 008', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Aline', 'Irakoze', 'F', NULL, 'etudiant', 10, NULL, 'actif', 1, 0, NULL, NULL, NULL, NULL, NULL, '2026-10-20 16:30:40', '2026-10-23 13:34:35'),
(10, 'd2f39452-cc92-11f1-bdf4-4c327596066b', 'parent.test', 'parent@uia.edu.bi', '+257 79 100 009', '$2y$10$92IXUNpkjO0rOQ5byMi.Ye4oKoEa3Ro9llC/.og/at2.uheWG/igi', 'Bernard', 'Nzigamasabo', 'M', NULL, 'parent', 9, NULL, 'actif', 1, 0, NULL, NULL, NULL, NULL, NULL, '2026-10-20 16:30:40', '2026-10-23 13:34:35');

--
-- Déclencheurs `users`
--
DELIMITER $$
CREATE TRIGGER `trg_users_bi` BEFORE INSERT ON `users` FOR EACH ROW BEGIN
  IF NEW.`role_id` IS NULL THEN
    SET NEW.`role_id` = (SELECT `id` FROM `roles` WHERE `slug`=NEW.`category` LIMIT 1);
  ELSE
    SET NEW.`category` = (SELECT `slug` FROM `roles` WHERE `id`=NEW.`role_id` LIMIT 1);
  END IF;
  IF NEW.`category` IN ('super_admin','admin') AND NEW.`category` <> 'system_admin' THEN
    SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT='Créer un administrateur via admin_users, pas via users';
  END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_users_bu` BEFORE UPDATE ON `users` FOR EACH ROW BEGIN
  IF NOT (NEW.`role_id` <=> OLD.`role_id`) THEN
    SET NEW.`category` = (SELECT `slug` FROM `roles` WHERE `id`=NEW.`role_id` LIMIT 1);
  ELSEIF NOT (NEW.`category` <=> OLD.`category`) THEN
    SET NEW.`role_id` = (SELECT `id` FROM `roles` WHERE `slug`=NEW.`category` LIMIT 1);
  END IF;
  IF NOT (NEW.`password_hash` <=> OLD.`password_hash`) THEN
    SET NEW.`password_changed_at` = NOW();
    SET NEW.`must_change_password` = 0;
  END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Doublure de structure pour la vue `v_admin_directory`
-- (Voir ci-dessous la vue réelle)
--
CREATE TABLE `v_admin_directory` (
`admin_user_id` int(10) unsigned
,`uuid` char(36)
,`user_name` varchar(100)
,`full_name` varchar(201)
,`email` varchar(150)
,`phone` varchar(30)
,`admin_role` enum('admin','super_admin')
,`status` enum('actif','désactivé','suspendu')
,`campus_name` varchar(150)
,`must_change_password` tinyint(1)
,`last_login_at` datetime
,`shadow_user_id` int(10) unsigned
,`created_at` datetime
);

-- --------------------------------------------------------

--
-- Doublure de structure pour la vue `v_attendance_rate`
-- (Voir ci-dessous la vue réelle)
--
CREATE TABLE `v_attendance_rate` (
`student_id` int(10) unsigned
,`course_id` int(10) unsigned
,`nb_sessions` bigint(21)
,`nb_present` decimal(23,0)
,`attendance_rate` decimal(28,1)
);

-- --------------------------------------------------------

--
-- Doublure de structure pour la vue `v_book_availability`
-- (Voir ci-dessous la vue réelle)
--
CREATE TABLE `v_book_availability` (
`book_id` int(10) unsigned
,`title` varchar(255)
,`author` varchar(200)
,`category` varchar(100)
,`shelf_location` varchar(50)
,`campus_id` int(10) unsigned
,`total_copies` smallint(5) unsigned
,`available_copies` smallint(5) unsigned
,`on_loan` int(6) unsigned
,`reservations_open` bigint(21)
);

-- --------------------------------------------------------

--
-- Doublure de structure pour la vue `v_borrower_unpaid_fines`
-- (Voir ci-dessous la vue réelle)
--
CREATE TABLE `v_borrower_unpaid_fines` (
`student_id` int(10) unsigned
,`user_id` int(10) unsigned
,`borrower_name` varchar(201)
,`nb_fines` bigint(21)
,`total_unpaid` decimal(32,2)
,`currency` char(3)
);

-- --------------------------------------------------------

--
-- Doublure de structure pour la vue `v_contracts_expiring`
-- (Voir ci-dessous la vue réelle)
--
CREATE TABLE `v_contracts_expiring` (
`contract_id` int(10) unsigned
,`user_id` int(10) unsigned
,`full_name` varchar(201)
,`contract_type` enum('CDI','CDD','vacation','stage','mission')
,`end_date` date
,`days_left` int(7)
);

-- --------------------------------------------------------

--
-- Doublure de structure pour la vue `v_enrollment_dossier`
-- (Voir ci-dessous la vue réelle)
--
CREATE TABLE `v_enrollment_dossier` (
`enrollment_id` int(10) unsigned
,`matricule` varchar(30)
,`student_name` varchar(201)
,`academic_year_id` int(10) unsigned
,`enrollment_type` enum('nouvelle','réinscription','redoublement','transfert')
,`level` enum('L1','L2','L3','M1','M2','D')
,`enrollment_status` enum('en_attente','validée','annulée')
,`missing_count` bigint(21)
,`dossier_status` varchar(9)
,`documents_waiver_until` date
);

-- --------------------------------------------------------

--
-- Doublure de structure pour la vue `v_enrollment_missing_docs`
-- (Voir ci-dessous la vue réelle)
--
CREATE TABLE `v_enrollment_missing_docs` (
`enrollment_id` int(10) unsigned
,`student_id` int(10) unsigned
,`academic_year_id` int(10) unsigned
,`unit_key` varchar(30)
,`missing_document` mediumtext
,`quantity_needed` tinyint(3) unsigned
);

-- --------------------------------------------------------

--
-- Doublure de structure pour la vue `v_enrollment_requirements`
-- (Voir ci-dessous la vue réelle)
--
CREATE TABLE `v_enrollment_requirements` (
`enrollment_id` int(10) unsigned
,`student_id` int(10) unsigned
,`academic_year_id` int(10) unsigned
,`requirement_id` int(10) unsigned
,`document_type_id` smallint(5) unsigned
,`doc_code` varchar(30)
,`doc_label` varchar(150)
,`min_quantity` tinyint(3) unsigned
,`unit_key` varchar(30)
,`is_provided` int(1)
);

-- --------------------------------------------------------

--
-- Doublure de structure pour la vue `v_leave_balance`
-- (Voir ci-dessous la vue réelle)
--
CREATE TABLE `v_leave_balance` (
`user_id` int(10) unsigned
,`full_name` varchar(201)
,`leave_type` varchar(20)
,`year_no` int(4)
,`days_allowed` smallint(5) unsigned
,`days_taken` decimal(27,0)
,`days_pending` decimal(27,0)
,`days_left` decimal(28,0)
);

-- --------------------------------------------------------

--
-- Doublure de structure pour la vue `v_overdue_loans`
-- (Voir ci-dessous la vue réelle)
--
CREATE TABLE `v_overdue_loans` (
`loan_id` bigint(20) unsigned
,`title` varchar(255)
,`barcode` varchar(40)
,`borrower_name` varchar(201)
,`borrower_type` varchar(20)
,`due_date` date
,`days_late` int(7)
,`estimated_fine` decimal(16,2)
);

-- --------------------------------------------------------

--
-- Doublure de structure pour la vue `v_payroll_summary`
-- (Voir ci-dessous la vue réelle)
--
CREATE TABLE `v_payroll_summary` (
`period_id` int(10) unsigned
,`label` varchar(50)
,`period_status` enum('ouverte','calculée','validée','payée')
,`nb_payslips` bigint(21)
,`total_gains` decimal(34,2)
,`total_deductions` decimal(34,2)
,`total_net` decimal(34,2)
,`currency` char(3)
);

-- --------------------------------------------------------

--
-- Doublure de structure pour la vue `v_semester_credit_check`
-- (Voir ci-dessous la vue réelle)
--
CREATE TABLE `v_semester_credit_check` (
`program_id` int(10) unsigned
,`program_name` varchar(150)
,`level` enum('L1','L2','L3','M1','M2','D')
,`semester_rank` tinyint(3) unsigned
,`credits_programmed` decimal(47,0)
,`credits_expected` bigint(20) unsigned
,`check_status` varchar(5)
);

-- --------------------------------------------------------

--
-- Doublure de structure pour la vue `v_staff_attendance_month`
-- (Voir ci-dessous la vue réelle)
--
CREATE TABLE `v_staff_attendance_month` (
`user_id` int(10) unsigned
,`full_name` varchar(201)
,`period` varchar(7)
,`days_present` decimal(23,0)
,`days_late` decimal(23,0)
,`days_absent` decimal(23,0)
,`days_leave` decimal(23,0)
);

-- --------------------------------------------------------

--
-- Doublure de structure pour la vue `v_staff_directory`
-- (Voir ci-dessous la vue réelle)
--
CREATE TABLE `v_staff_directory` (
`user_id` int(10) unsigned
,`employee_no` varchar(30)
,`full_name` varchar(201)
,`email` varchar(150)
,`phone` varchar(30)
,`staff_category` enum('enseignant','administratif','technique','appui','direction')
,`job_title` varchar(150)
,`service_name` varchar(150)
,`department_name` varchar(150)
,`campus_name` varchar(150)
,`hire_date` date
,`years_of_service` bigint(21)
,`employment_status` enum('actif','en_congé','suspendu','retraité','démissionné','licencié','décédé')
);

-- --------------------------------------------------------

--
-- Doublure de structure pour la vue `v_student_balance`
-- (Voir ci-dessous la vue réelle)
--
CREATE TABLE `v_student_balance` (
`student_id` int(10) unsigned
,`matricule` varchar(30)
,`student_name` varchar(201)
,`academic_year_id` int(10) unsigned
,`currency` char(3)
,`total_due` decimal(34,2)
,`total_paid` decimal(34,2)
,`balance` decimal(35,2)
);

-- --------------------------------------------------------

--
-- Doublure de structure pour la vue `v_syllabus_progress`
-- (Voir ci-dessous la vue réelle)
--
CREATE TABLE `v_syllabus_progress` (
`course_id` int(10) unsigned
,`course_code` varchar(20)
,`course_title` varchar(200)
,`planned_hours` decimal(27,0)
,`covered_hours` decimal(27,0)
,`progress_pct` decimal(32,1)
);

-- --------------------------------------------------------

--
-- Doublure de structure pour la vue `v_teacher_hours`
-- (Voir ci-dessous la vue réelle)
--
CREATE TABLE `v_teacher_hours` (
`teacher_id` int(10) unsigned
,`teacher_name` varchar(201)
,`period` varchar(7)
,`payroll_status` enum('à_valider','validée','payée')
,`hours_done` decimal(27,2)
,`hourly_rate` decimal(12,2)
,`currency` char(3)
,`amount_due` decimal(38,2)
);

-- --------------------------------------------------------

--
-- Doublure de structure pour la vue `v_transcript`
-- (Voir ci-dessous la vue réelle)
--
CREATE TABLE `v_transcript` (
`student_id` int(10) unsigned
,`matricule` varchar(30)
,`student_name` varchar(201)
,`academic_year_id` int(10) unsigned
,`level` enum('L1','L2','L3','M1','M2','D')
,`semester_rank` tinyint(3) unsigned
,`unit_code` varchar(20)
,`unit_title` varchar(200)
,`course_code` varchar(20)
,`course_title` varchar(200)
,`coefficient` decimal(4,2)
,`credits` tinyint(3) unsigned
,`hours_total` smallint(5) unsigned
,`session_no` tinyint(3) unsigned
,`average` decimal(5,2)
,`credits_earned` tinyint(3) unsigned
,`status` enum('validé','rattrapage','ajourné')
,`is_compensated` tinyint(1)
);

-- --------------------------------------------------------

--
-- Doublure de structure pour la vue `v_unit_summary`
-- (Voir ci-dessous la vue réelle)
--
CREATE TABLE `v_unit_summary` (
`unit_id` int(10) unsigned
,`unit_code` varchar(20)
,`unit_title` varchar(200)
,`program_id` int(10) unsigned
,`program_name` varchar(150)
,`level` enum('L1','L2','L3','M1','M2','D')
,`semester_rank` tinyint(3) unsigned
,`category` enum('fondamentale','méthodologique','découverte','transversale','optionnelle','libre')
,`nb_courses` bigint(21)
,`total_credits` decimal(25,0)
,`total_coefficient` decimal(26,2)
,`hours_cm` decimal(27,0)
,`hours_td` decimal(27,0)
,`hours_tp` decimal(27,0)
,`hours_tpe` decimal(27,0)
,`hours_contact_total` decimal(27,0)
);

-- --------------------------------------------------------

--
-- Structure de la table `year_results`
--

CREATE TABLE `year_results` (
  `id` bigint(20) UNSIGNED NOT NULL,
  `student_id` int(10) UNSIGNED NOT NULL,
  `academic_year_id` int(10) UNSIGNED NOT NULL,
  `program_id` int(10) UNSIGNED NOT NULL,
  `level` enum('L1','L2','L3','M1','M2','D') NOT NULL,
  `session_no` tinyint(3) UNSIGNED NOT NULL DEFAULT 1,
  `average` decimal(5,2) DEFAULT NULL,
  `credits_required` smallint(5) UNSIGNED NOT NULL DEFAULT 0,
  `credits_earned` smallint(5) UNSIGNED NOT NULL DEFAULT 0,
  `decision` enum('admis','admis_avec_dettes','rattrapage','ajourné') NOT NULL,
  `mention_label` varchar(80) DEFAULT NULL,
  `computed_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Structure de la vue `v_admin_directory`
--
DROP TABLE IF EXISTS `v_admin_directory`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_admin_directory`  AS SELECT `a`.`id` AS `admin_user_id`, `a`.`uuid` AS `uuid`, `a`.`user_name` AS `user_name`, concat(`a`.`l_name`,' ',`a`.`f_name`) AS `full_name`, `a`.`email` AS `email`, `a`.`phone` AS `phone`, `a`.`admin_role` AS `admin_role`, `a`.`status` AS `status`, `c`.`name` AS `campus_name`, `a`.`must_change_password` AS `must_change_password`, `a`.`last_login_at` AS `last_login_at`, `a`.`shadow_user_id` AS `shadow_user_id`, `a`.`created_at` AS `created_at` FROM (`admin_users` `a` left join `campuses` `c` on(`c`.`id` = `a`.`campus_id`)) ;

-- --------------------------------------------------------

--
-- Structure de la vue `v_attendance_rate`
--
DROP TABLE IF EXISTS `v_attendance_rate`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_attendance_rate`  AS SELECT `a`.`student_id` AS `student_id`, `cs`.`course_id` AS `course_id`, count(0) AS `nb_sessions`, sum(`a`.`status` in ('présent','retard')) AS `nb_present`, round(100 * sum(`a`.`status` in ('présent','retard')) / count(0),1) AS `attendance_rate` FROM (`attendance` `a` join `class_sessions` `cs` on(`cs`.`id` = `a`.`class_session_id`)) WHERE `cs`.`status` = 'tenue' GROUP BY `a`.`student_id`, `cs`.`course_id` ;

-- --------------------------------------------------------

--
-- Structure de la vue `v_book_availability`
--
DROP TABLE IF EXISTS `v_book_availability`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_book_availability`  AS SELECT `b`.`id` AS `book_id`, `b`.`title` AS `title`, `b`.`author` AS `author`, `b`.`category` AS `category`, `b`.`shelf_location` AS `shelf_location`, `b`.`campus_id` AS `campus_id`, `b`.`total_copies` AS `total_copies`, `b`.`available_copies` AS `available_copies`, `b`.`total_copies`- `b`.`available_copies` AS `on_loan`, (select count(0) from `book_reservations` `r` where `r`.`book_id` = `b`.`id` and `r`.`status` in ('en_attente','disponible')) AS `reservations_open` FROM `books` AS `b` WHERE `b`.`is_active` = 1 ;

-- --------------------------------------------------------

--
-- Structure de la vue `v_borrower_unpaid_fines`
--
DROP TABLE IF EXISTS `v_borrower_unpaid_fines`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_borrower_unpaid_fines`  AS SELECT `f`.`student_id` AS `student_id`, `f`.`user_id` AS `user_id`, coalesce(concat(`st`.`last_name`,' ',`st`.`first_name`),concat(`u`.`l_name`,' ',`u`.`f_name`)) AS `borrower_name`, count(0) AS `nb_fines`, sum(`f`.`amount`) AS `total_unpaid`, max(`f`.`currency`) AS `currency` FROM ((`library_fines` `f` left join `students` `st` on(`st`.`id` = `f`.`student_id`)) left join `users` `u` on(`u`.`id` = `f`.`user_id`)) WHERE `f`.`status` = 'impayée' GROUP BY `f`.`student_id`, `f`.`user_id`, coalesce(concat(`st`.`last_name`,' ',`st`.`first_name`),concat(`u`.`l_name`,' ',`u`.`f_name`)) ;

-- --------------------------------------------------------

--
-- Structure de la vue `v_contracts_expiring`
--
DROP TABLE IF EXISTS `v_contracts_expiring`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_contracts_expiring`  AS SELECT `ct`.`id` AS `contract_id`, `ct`.`user_id` AS `user_id`, concat(`u`.`l_name`,' ',`u`.`f_name`) AS `full_name`, `ct`.`contract_type` AS `contract_type`, `ct`.`end_date` AS `end_date`, to_days(`ct`.`end_date`) - to_days(curdate()) AS `days_left` FROM (`staff_contracts` `ct` join `users` `u` on(`u`.`id` = `ct`.`user_id`)) WHERE `ct`.`status` = 'actif' AND `ct`.`end_date` is not null AND `ct`.`end_date` between curdate() and curdate() + interval 60 day ;

-- --------------------------------------------------------

--
-- Structure de la vue `v_enrollment_dossier`
--
DROP TABLE IF EXISTS `v_enrollment_dossier`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_enrollment_dossier`  AS SELECT `e`.`id` AS `enrollment_id`, `st`.`matricule` AS `matricule`, concat(`st`.`last_name`,' ',`st`.`first_name`) AS `student_name`, `e`.`academic_year_id` AS `academic_year_id`, `e`.`enrollment_type` AS `enrollment_type`, `e`.`level` AS `level`, `e`.`status` AS `enrollment_status`, (select count(0) from `v_enrollment_missing_docs` `m` where `m`.`enrollment_id` = `e`.`id`) AS `missing_count`, if((select count(0) from `v_enrollment_missing_docs` `m` where `m`.`enrollment_id` = `e`.`id`) = 0,'complet','incomplet') AS `dossier_status`, `e`.`documents_waiver_until` AS `documents_waiver_until` FROM (`enrollments` `e` join `students` `st` on(`st`.`id` = `e`.`student_id`)) ;

-- --------------------------------------------------------

--
-- Structure de la vue `v_enrollment_missing_docs`
--
DROP TABLE IF EXISTS `v_enrollment_missing_docs`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_enrollment_missing_docs`  AS SELECT `v_enrollment_requirements`.`enrollment_id` AS `enrollment_id`, `v_enrollment_requirements`.`student_id` AS `student_id`, `v_enrollment_requirements`.`academic_year_id` AS `academic_year_id`, `v_enrollment_requirements`.`unit_key` AS `unit_key`, group_concat(`v_enrollment_requirements`.`doc_label` order by `v_enrollment_requirements`.`doc_label` ASC separator ' OU ') AS `missing_document`, max(`v_enrollment_requirements`.`min_quantity`) AS `quantity_needed` FROM `v_enrollment_requirements` GROUP BY `v_enrollment_requirements`.`enrollment_id`, `v_enrollment_requirements`.`student_id`, `v_enrollment_requirements`.`academic_year_id`, `v_enrollment_requirements`.`unit_key` HAVING sum(`v_enrollment_requirements`.`is_provided`) = 0 ;

-- --------------------------------------------------------

--
-- Structure de la vue `v_enrollment_requirements`
--
DROP TABLE IF EXISTS `v_enrollment_requirements`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_enrollment_requirements`  AS SELECT `e`.`id` AS `enrollment_id`, `e`.`student_id` AS `student_id`, `e`.`academic_year_id` AS `academic_year_id`, `r`.`id` AS `requirement_id`, `r`.`document_type_id` AS `document_type_id`, `dt`.`code` AS `doc_code`, `dt`.`label` AS `doc_label`, `r`.`min_quantity` AS `min_quantity`, coalesce(`r`.`alt_group`,concat('R',`r`.`id`)) AS `unit_key`, exists(select 1 from `enrollment_documents` `d` where `d`.`student_id` = `e`.`student_id` and `d`.`document_type_id` = `r`.`document_type_id` and `d`.`status` in ('reçu','validé') and `d`.`quantity` >= `r`.`min_quantity` and (`dt`.`is_one_time` = 1 or `d`.`academic_year_id` = `e`.`academic_year_id`) limit 1) AS `is_provided` FROM ((((((`enrollments` `e` join `students` `st` on(`st`.`id` = `e`.`student_id`)) join `programs` `p` on(`p`.`id` = `e`.`program_id`)) join `departments` `dp` on(`dp`.`id` = `p`.`department_id`)) join `faculties` `f` on(`f`.`id` = `dp`.`faculty_id`)) join `document_requirements` `r` on(`r`.`is_active` = 1 and `r`.`is_mandatory` = 1 and (`r`.`institution_type` is null or `r`.`institution_type` = `f`.`institution_type`) and (`r`.`cycle` is null or `r`.`cycle` = case when `e`.`level` in ('L1','L2','L3') then 'licence' when `e`.`level` in ('M1','M2') then 'master' else 'doctorat' end) and (`r`.`enrollment_type` is null or `r`.`enrollment_type` = `e`.`enrollment_type`) and (`r`.`foreign_only` = 0 or coalesce(`st`.`nationality`,'Burundaise')  not like 'Burund%'))) join `document_types` `dt` on(`dt`.`id` = `r`.`document_type_id`)) ;

-- --------------------------------------------------------

--
-- Structure de la vue `v_leave_balance`
--
DROP TABLE IF EXISTS `v_leave_balance`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_leave_balance`  AS SELECT `sp`.`user_id` AS `user_id`, concat(`u`.`l_name`,' ',`u`.`f_name`) AS `full_name`, `lt`.`code` AS `leave_type`, year(curdate()) AS `year_no`, `lt`.`days_per_year` AS `days_allowed`, coalesce(sum(if(`lr`.`status` = 'approuvé',`lr`.`days_count`,0)),0) AS `days_taken`, coalesce(sum(if(`lr`.`status` = 'en_attente',`lr`.`days_count`,0)),0) AS `days_pending`, `lt`.`days_per_year`- coalesce(sum(if(`lr`.`status` in ('approuvé','en_attente'),`lr`.`days_count`,0)),0) AS `days_left` FROM (((`staff_profiles` `sp` join `users` `u` on(`u`.`id` = `sp`.`user_id`)) join `leave_types` `lt` on(`lt`.`days_per_year` is not null)) left join `leave_requests` `lr` on(`lr`.`user_id` = `sp`.`user_id` and `lr`.`leave_type_id` = `lt`.`id` and year(`lr`.`start_date`) = year(curdate()))) GROUP BY `sp`.`user_id`, `u`.`l_name`, `u`.`f_name`, `lt`.`code`, `lt`.`days_per_year` ;

-- --------------------------------------------------------

--
-- Structure de la vue `v_overdue_loans`
--
DROP TABLE IF EXISTS `v_overdue_loans`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_overdue_loans`  AS SELECT `l`.`id` AS `loan_id`, `b`.`title` AS `title`, `c`.`barcode` AS `barcode`, coalesce(concat(`st`.`last_name`,' ',`st`.`first_name`),concat(`u`.`l_name`,' ',`u`.`f_name`)) AS `borrower_name`, `fn_borrower_type`(`l`.`student_id`,`l`.`user_id`) AS `borrower_type`, `l`.`due_date` AS `due_date`, to_days(curdate()) - to_days(`l`.`due_date`) AS `days_late`, (to_days(curdate()) - to_days(`l`.`due_date`)) * coalesce((select `p`.`fine_per_day` from `loan_policies` `p` where `p`.`borrower_type` = `fn_borrower_type`(`l`.`student_id`,`l`.`user_id`)),0) AS `estimated_fine` FROM ((((`book_loans` `l` join `books` `b` on(`b`.`id` = `l`.`book_id`)) left join `book_copies` `c` on(`c`.`id` = `l`.`copy_id`)) left join `students` `st` on(`st`.`id` = `l`.`student_id`)) left join `users` `u` on(`u`.`id` = `l`.`user_id`)) WHERE `l`.`returned_at` is null AND `l`.`due_date` < curdate() ;

-- --------------------------------------------------------

--
-- Structure de la vue `v_payroll_summary`
--
DROP TABLE IF EXISTS `v_payroll_summary`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_payroll_summary`  AS SELECT `pp`.`id` AS `period_id`, `pp`.`label` AS `label`, `pp`.`status` AS `period_status`, count(`ps`.`id`) AS `nb_payslips`, coalesce(sum(`ps`.`total_gains`),0) AS `total_gains`, coalesce(sum(`ps`.`total_deductions`),0) AS `total_deductions`, coalesce(sum(`ps`.`net_pay`),0) AS `total_net`, max(`ps`.`currency`) AS `currency` FROM (`payroll_periods` `pp` left join `payslips` `ps` on(`ps`.`period_id` = `pp`.`id`)) GROUP BY `pp`.`id`, `pp`.`label`, `pp`.`status` ;

-- --------------------------------------------------------

--
-- Structure de la vue `v_semester_credit_check`
--
DROP TABLE IF EXISTS `v_semester_credit_check`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_semester_credit_check`  AS SELECT `s`.`program_id` AS `program_id`, `s`.`program_name` AS `program_name`, `s`.`level` AS `level`, `s`.`semester_rank` AS `semester_rank`, sum(`s`.`total_credits`) AS `credits_programmed`, cast((select `settings`.`value` from `settings` where `settings`.`key_name` = 'credits_per_semester') as unsigned) AS `credits_expected`, if(sum(`s`.`total_credits`) = cast((select `settings`.`value` from `settings` where `settings`.`key_name` = 'credits_per_semester') as unsigned),'OK','ÉCART') AS `check_status` FROM `v_unit_summary` AS `s` GROUP BY `s`.`program_id`, `s`.`program_name`, `s`.`level`, `s`.`semester_rank` ;

-- --------------------------------------------------------

--
-- Structure de la vue `v_staff_attendance_month`
--
DROP TABLE IF EXISTS `v_staff_attendance_month`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_staff_attendance_month`  AS SELECT `a`.`user_id` AS `user_id`, concat(`u`.`l_name`,' ',`u`.`f_name`) AS `full_name`, date_format(`a`.`work_date`,'%Y-%m') AS `period`, sum(`a`.`status` = 'présent') AS `days_present`, sum(`a`.`status` = 'retard') AS `days_late`, sum(`a`.`status` = 'absent') AS `days_absent`, sum(`a`.`status` = 'congé') AS `days_leave` FROM (`staff_attendance` `a` join `users` `u` on(`u`.`id` = `a`.`user_id`)) GROUP BY `a`.`user_id`, `u`.`l_name`, `u`.`f_name`, date_format(`a`.`work_date`,'%Y-%m') ;

-- --------------------------------------------------------

--
-- Structure de la vue `v_staff_directory`
--
DROP TABLE IF EXISTS `v_staff_directory`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_staff_directory`  AS SELECT `sp`.`user_id` AS `user_id`, `sp`.`employee_no` AS `employee_no`, concat(`u`.`l_name`,' ',`u`.`f_name`) AS `full_name`, `u`.`email` AS `email`, `u`.`phone` AS `phone`, `sp`.`staff_category` AS `staff_category`, `jt`.`label` AS `job_title`, `sv`.`name` AS `service_name`, `dp`.`name` AS `department_name`, `c`.`name` AS `campus_name`, `sp`.`hire_date` AS `hire_date`, timestampdiff(YEAR,`sp`.`hire_date`,curdate()) AS `years_of_service`, `sp`.`employment_status` AS `employment_status` FROM (((((`staff_profiles` `sp` join `users` `u` on(`u`.`id` = `sp`.`user_id`)) left join `job_titles` `jt` on(`jt`.`id` = `sp`.`job_title_id`)) left join `services` `sv` on(`sv`.`id` = `sp`.`service_id`)) left join `departments` `dp` on(`dp`.`id` = `sp`.`department_id`)) left join `campuses` `c` on(`c`.`id` = `sp`.`campus_id`)) ;

-- --------------------------------------------------------

--
-- Structure de la vue `v_student_balance`
--
DROP TABLE IF EXISTS `v_student_balance`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_student_balance`  AS SELECT `i`.`student_id` AS `student_id`, `st`.`matricule` AS `matricule`, concat(`st`.`last_name`,' ',`st`.`first_name`) AS `student_name`, `i`.`academic_year_id` AS `academic_year_id`, `i`.`currency` AS `currency`, sum(`i`.`amount_due`) AS `total_due`, sum(`i`.`amount_paid`) AS `total_paid`, sum(`i`.`amount_due` - `i`.`amount_paid`) AS `balance` FROM (`invoices` `i` join `students` `st` on(`st`.`id` = `i`.`student_id`)) WHERE `i`.`status` <> 'annulée' GROUP BY `i`.`student_id`, `st`.`matricule`, `st`.`last_name`, `st`.`first_name`, `i`.`academic_year_id`, `i`.`currency` ;

-- --------------------------------------------------------

--
-- Structure de la vue `v_syllabus_progress`
--
DROP TABLE IF EXISTS `v_syllabus_progress`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_syllabus_progress`  AS SELECT `s`.`course_id` AS `course_id`, `c`.`code` AS `course_code`, `c`.`title` AS `course_title`, sum(`s`.`planned_hours`) AS `planned_hours`, sum(`s`.`covered_hours`) AS `covered_hours`, round(100 * sum(`s`.`covered_hours`) / nullif(sum(`s`.`planned_hours`),0),1) AS `progress_pct` FROM (`syllabus` `s` join `courses` `c` on(`c`.`id` = `s`.`course_id`)) GROUP BY `s`.`course_id`, `c`.`code`, `c`.`title` ;

-- --------------------------------------------------------

--
-- Structure de la vue `v_teacher_hours`
--
DROP TABLE IF EXISTS `v_teacher_hours`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_teacher_hours`  AS SELECT `cs`.`teacher_id` AS `teacher_id`, concat(`u`.`f_name`,' ',`u`.`l_name`) AS `teacher_name`, date_format(`cs`.`session_date`,'%Y-%m') AS `period`, `cs`.`payroll_status` AS `payroll_status`, sum(`cs`.`hours`) AS `hours_done`, `tp`.`hourly_rate` AS `hourly_rate`, `tp`.`currency` AS `currency`, round(sum(`cs`.`hours`) * coalesce(`tp`.`hourly_rate`,0),2) AS `amount_due` FROM ((`class_sessions` `cs` join `users` `u` on(`u`.`id` = `cs`.`teacher_id`)) left join `teacher_profiles` `tp` on(`tp`.`user_id` = `cs`.`teacher_id`)) WHERE `cs`.`status` = 'tenue' GROUP BY `cs`.`teacher_id`, `u`.`f_name`, `u`.`l_name`, date_format(`cs`.`session_date`,'%Y-%m'), `cs`.`payroll_status`, `tp`.`hourly_rate`, `tp`.`currency` ;

-- --------------------------------------------------------

--
-- Structure de la vue `v_transcript`
--
DROP TABLE IF EXISTS `v_transcript`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_transcript`  AS SELECT `cr`.`student_id` AS `student_id`, `st`.`matricule` AS `matricule`, concat(`st`.`last_name`,' ',`st`.`first_name`) AS `student_name`, `cr`.`academic_year_id` AS `academic_year_id`, `u`.`level` AS `level`, `u`.`semester_rank` AS `semester_rank`, `u`.`code` AS `unit_code`, `u`.`title` AS `unit_title`, `c`.`code` AS `course_code`, `c`.`title` AS `course_title`, `c`.`coefficient` AS `coefficient`, `c`.`credits` AS `credits`, `c`.`hours_total` AS `hours_total`, `cr`.`session_no` AS `session_no`, `cr`.`average` AS `average`, `cr`.`credits_earned` AS `credits_earned`, `cr`.`status` AS `status`, `cr`.`is_compensated` AS `is_compensated` FROM (((`course_results` `cr` join `students` `st` on(`st`.`id` = `cr`.`student_id`)) join `courses` `c` on(`c`.`id` = `cr`.`course_id`)) left join `teaching_units` `u` on(`u`.`id` = `c`.`unit_id`)) WHERE `cr`.`session_no` = (select max(`x`.`session_no`) from `course_results` `x` where `x`.`student_id` = `cr`.`student_id` AND `x`.`course_id` = `cr`.`course_id` AND `x`.`academic_year_id` = `cr`.`academic_year_id`) ;

-- --------------------------------------------------------

--
-- Structure de la vue `v_unit_summary`
--
DROP TABLE IF EXISTS `v_unit_summary`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `v_unit_summary`  AS SELECT `u`.`id` AS `unit_id`, `u`.`code` AS `unit_code`, `u`.`title` AS `unit_title`, `u`.`program_id` AS `program_id`, `p`.`name` AS `program_name`, `u`.`level` AS `level`, `u`.`semester_rank` AS `semester_rank`, `u`.`category` AS `category`, count(`c`.`id`) AS `nb_courses`, coalesce(sum(`c`.`credits`),0) AS `total_credits`, round(coalesce(sum(`c`.`coefficient`),0),2) AS `total_coefficient`, coalesce(sum(`c`.`hours_cm`),0) AS `hours_cm`, coalesce(sum(`c`.`hours_td`),0) AS `hours_td`, coalesce(sum(`c`.`hours_tp`),0) AS `hours_tp`, coalesce(sum(`c`.`hours_tpe`),0) AS `hours_tpe`, coalesce(sum(`c`.`hours_total`),0) AS `hours_contact_total` FROM ((`teaching_units` `u` join `programs` `p` on(`p`.`id` = `u`.`program_id`)) left join `courses` `c` on(`c`.`unit_id` = `u`.`id` and `c`.`is_active` = 1)) WHERE `u`.`is_active` = 1 GROUP BY `u`.`id`, `u`.`code`, `u`.`title`, `u`.`program_id`, `p`.`name`, `u`.`level`, `u`.`semester_rank`, `u`.`category` ;

--
-- Index pour les tables déchargées
--

--
-- Index pour la table `academic_calendar`
--
ALTER TABLE `academic_calendar`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_cal_year_type` (`academic_year_id`,`type`),
  ADD KEY `idx_cal_dates` (`start_date`,`end_date`),
  ADD KEY `fk_cal_campus` (`campus_id`),
  ADD KEY `fk_cal_creator` (`created_by`);

--
-- Index pour la table `academic_years`
--
ALTER TABLE `academic_years`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `label` (`label`),
  ADD UNIQUE KEY `uk_one_current_year` (`current_flag`);

--
-- Index pour la table `activity_logs`
--
ALTER TABLE `activity_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_logs_user` (`user_id`),
  ADD KEY `idx_logs_action` (`action`),
  ADD KEY `idx_logs_created` (`created_at`);

--
-- Index pour la table `admin_activity_logs`
--
ALTER TABLE `admin_activity_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_aal_admin` (`admin_user_id`),
  ADD KEY `idx_aal_action` (`action`),
  ADD KEY `idx_aal_created` (`created_at`);

--
-- Index pour la table `admin_users`
--
ALTER TABLE `admin_users`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_admin_uuid` (`uuid`),
  ADD UNIQUE KEY `uk_admin_username` (`user_name`),
  ADD UNIQUE KEY `uk_admin_email` (`email`),
  ADD UNIQUE KEY `uk_admin_shadow` (`shadow_user_id`),
  ADD KEY `idx_admin_role` (`admin_role`),
  ADD KEY `idx_admin_status` (`status`),
  ADD KEY `idx_admin_campus` (`campus_id`);

--
-- Index pour la table `admission_applications`
--
ALTER TABLE `admission_applications`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_admission_ref` (`reference`),
  ADD KEY `idx_adm_campus_program` (`campus_id`,`program_id`),
  ADD KEY `idx_adm_status` (`status`),
  ADD KEY `fk_adm_program` (`program_id`),
  ADD KEY `fk_adm_student` (`student_id`),
  ADD KEY `fk_adm_reviewer` (`reviewed_by`);

--
-- Index pour la table `alerts`
--
ALTER TABLE `alerts`
  ADD PRIMARY KEY (`id`),
  ADD KEY `target_user_id` (`target_user_id`),
  ADD KEY `campus_id` (`campus_id`),
  ADD KEY `idx_alerts_active` (`is_dismissed`,`priority`);

--
-- Index pour la table `announcements`
--
ALTER TABLE `announcements`
  ADD PRIMARY KEY (`id`),
  ADD KEY `campus_id` (`campus_id`),
  ADD KEY `program_id` (`program_id`),
  ADD KEY `created_by` (`created_by`);

--
-- Index pour la table `attendance`
--
ALTER TABLE `attendance`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_attendance` (`class_session_id`,`student_id`),
  ADD KEY `idx_att_student` (`student_id`),
  ADD KEY `fk_att_recorder` (`recorded_by`);

--
-- Index pour la table `books`
--
ALTER TABLE `books`
  ADD PRIMARY KEY (`id`),
  ADD KEY `campus_id` (`campus_id`),
  ADD KEY `idx_books_title` (`title`),
  ADD KEY `idx_books_department` (`department_id`),
  ADD KEY `idx_books_isbn` (`isbn`);

--
-- Index pour la table `book_acquisitions`
--
ALTER TABLE `book_acquisitions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_acq_book` (`book_id`),
  ADD KEY `fk_acq_user` (`received_by`);

--
-- Index pour la table `book_copies`
--
ALTER TABLE `book_copies`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_copy_barcode` (`barcode`),
  ADD KEY `idx_copy_book_status` (`book_id`,`status`);

--
-- Index pour la table `book_loans`
--
ALTER TABLE `book_loans`
  ADD PRIMARY KEY (`id`),
  ADD KEY `book_id` (`book_id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `user_id` (`user_id`),
  ADD KEY `issued_by` (`issued_by`),
  ADD KEY `idx_loans_copy` (`copy_id`),
  ADD KEY `idx_loans_status_due` (`status`,`due_date`);

--
-- Index pour la table `book_reservations`
--
ALTER TABLE `book_reservations`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_res_book_status` (`book_id`,`status`,`reserved_at`),
  ADD KEY `idx_res_student` (`student_id`),
  ADD KEY `fk_res_user` (`user_id`);

--
-- Index pour la table `campuses`
--
ALTER TABLE `campuses`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `code` (`code`),
  ADD KEY `fk_campuses_director` (`director_id`);

--
-- Index pour la table `cash_operations`
--
ALTER TABLE `cash_operations`
  ADD PRIMARY KEY (`id`),
  ADD KEY `cash_register_id` (`cash_register_id`),
  ADD KEY `created_by` (`created_by`);

--
-- Index pour la table `cash_register`
--
ALTER TABLE `cash_register`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_cash_session` (`campus_id`,`session_date`),
  ADD KEY `opened_by` (`opened_by`),
  ADD KEY `closed_by` (`closed_by`);

--
-- Index pour la table `class_sessions`
--
ALTER TABLE `class_sessions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_cs_course_date` (`course_id`,`session_date`),
  ADD KEY `idx_cs_teacher_date` (`teacher_id`,`session_date`),
  ADD KEY `idx_cs_timetable` (`timetable_id`),
  ADD KEY `fk_cs_campus` (`campus_id`),
  ADD KEY `fk_cs_room` (`room_id`),
  ADD KEY `fk_cs_syllabus` (`syllabus_id`),
  ADD KEY `fk_cs_validator` (`validated_by`);

--
-- Index pour la table `courses`
--
ALTER TABLE `courses`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `code` (`code`),
  ADD KEY `program_id` (`program_id`),
  ADD KEY `semester_id` (`semester_id`),
  ADD KEY `idx_courses_unit` (`unit_id`);

--
-- Index pour la table `course_assignments`
--
ALTER TABLE `course_assignments`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_assignment` (`course_id`,`teacher_id`,`academic_year_id`),
  ADD KEY `teacher_id` (`teacher_id`),
  ADD KEY `academic_year_id` (`academic_year_id`),
  ADD KEY `campus_id` (`campus_id`);

--
-- Index pour la table `course_results`
--
ALTER TABLE `course_results`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_result_session` (`student_id`,`course_id`,`academic_year_id`,`session_no`),
  ADD KEY `course_id` (`course_id`),
  ADD KEY `academic_year_id` (`academic_year_id`),
  ADD KEY `semester_id` (`semester_id`);

--
-- Index pour la table `departments`
--
ALTER TABLE `departments`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `code` (`code`),
  ADD KEY `faculty_id` (`faculty_id`),
  ADD KEY `head_id` (`head_id`);

--
-- Index pour la table `device_tokens`
--
ALTER TABLE `device_tokens`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_token` (`token`),
  ADD KEY `user_id` (`user_id`);

--
-- Index pour la table `documents`
--
ALTER TABLE `documents`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD UNIQUE KEY `uk_doc_verification` (`verification_code`),
  ADD KEY `user_id` (`user_id`),
  ADD KEY `issued_by` (`issued_by`),
  ADD KEY `idx_docs_type` (`type`),
  ADD KEY `idx_docs_student` (`student_id`);

--
-- Index pour la table `document_requirements`
--
ALTER TABLE `document_requirements`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_req_scope` (`enrollment_type`,`cycle`,`institution_type`),
  ADD KEY `fk_req_doctype` (`document_type_id`);

--
-- Index pour la table `document_types`
--
ALTER TABLE `document_types`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_doctype_code` (`code`);

--
-- Index pour la table `enrollments`
--
ALTER TABLE `enrollments`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_enrollment` (`student_id`,`academic_year_id`,`program_id`),
  ADD KEY `program_id` (`program_id`),
  ADD KEY `academic_year_id` (`academic_year_id`),
  ADD KEY `campus_id` (`campus_id`),
  ADD KEY `validated_by` (`validated_by`),
  ADD KEY `fk_enroll_waiver_by` (`documents_waiver_by`);

--
-- Index pour la table `enrollment_documents`
--
ALTER TABLE `enrollment_documents`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_ed_student_type` (`student_id`,`document_type_id`),
  ADD KEY `idx_ed_admission` (`admission_id`),
  ADD KEY `idx_ed_enrollment` (`enrollment_id`),
  ADD KEY `idx_ed_year` (`academic_year_id`),
  ADD KEY `idx_ed_status` (`status`),
  ADD KEY `fk_ed_doctype` (`document_type_id`),
  ADD KEY `fk_ed_document` (`document_id`),
  ADD KEY `fk_ed_received_by` (`received_by`),
  ADD KEY `fk_ed_verified_by` (`verified_by`);

--
-- Index pour la table `evaluations`
--
ALTER TABLE `evaluations`
  ADD PRIMARY KEY (`id`),
  ADD KEY `course_id` (`course_id`),
  ADD KEY `teacher_id` (`teacher_id`),
  ADD KEY `idx_eval_course_year` (`course_id`,`academic_year_id`),
  ADD KEY `fk_eval_year` (`academic_year_id`);

--
-- Index pour la table `exam_schedules`
--
ALTER TABLE `exam_schedules`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_exam_date_room` (`exam_date`,`room_id`),
  ADD KEY `idx_exam_course` (`course_id`),
  ADD KEY `fk_exam_eval` (`evaluation_id`),
  ADD KEY `fk_exam_semester` (`semester_id`),
  ADD KEY `fk_exam_campus` (`campus_id`),
  ADD KEY `fk_exam_room` (`room_id`),
  ADD KEY `fk_exam_supervisor` (`supervisor_id`);

--
-- Index pour la table `faculties`
--
ALTER TABLE `faculties`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `code` (`code`),
  ADD KEY `dean_id` (`dean_id`),
  ADD KEY `campus_id` (`campus_id`);

--
-- Index pour la table `fee_structures`
--
ALTER TABLE `fee_structures`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_fee` (`program_id`,`academic_year_id`,`level`),
  ADD KEY `academic_year_id` (`academic_year_id`);

--
-- Index pour la table `grades`
--
ALTER TABLE `grades`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_grade` (`evaluation_id`,`student_id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `entered_by` (`entered_by`);

--
-- Index pour la table `grade_appeals`
--
ALTER TABLE `grade_appeals`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_appeal_eval` (`evaluation_id`),
  ADD KEY `idx_appeal_student` (`student_id`),
  ADD KEY `idx_appeal_status` (`status`),
  ADD KEY `fk_appeal_handler` (`handled_by`);

--
-- Index pour la table `grade_history`
--
ALTER TABLE `grade_history`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_gh_grade` (`grade_id`),
  ADD KEY `idx_gh_student` (`student_id`),
  ADD KEY `idx_gh_changed_at` (`changed_at`);

--
-- Index pour la table `grade_mentions`
--
ALTER TABLE `grade_mentions`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_mention_code` (`code`);

--
-- Index pour la table `internships`
--
ALTER TABLE `internships`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_intern_student` (`student_id`),
  ADD KEY `fk_intern_year` (`academic_year_id`),
  ADD KEY `fk_intern_supervisor` (`academic_supervisor_id`),
  ADD KEY `fk_intern_report` (`report_document_id`);

--
-- Index pour la table `invoices`
--
ALTER TABLE `invoices`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `reference` (`reference`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `academic_year_id` (`academic_year_id`),
  ADD KEY `created_by` (`created_by`),
  ADD KEY `idx_invoices_student_year` (`student_id`,`academic_year_id`),
  ADD KEY `idx_invoices_status` (`status`);

--
-- Index pour la table `invoice_installments`
--
ALTER TABLE `invoice_installments`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_installment` (`invoice_id`,`installment_no`),
  ADD KEY `idx_inst_due` (`due_date`,`status`);

--
-- Index pour la table `job_titles`
--
ALTER TABLE `job_titles`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_jobtitle_code` (`code`);

--
-- Index pour la table `juries`
--
ALTER TABLE `juries`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_jury` (`academic_year_id`,`campus_id`,`program_id`,`level`,`session_no`),
  ADD KEY `fk_jury_campus` (`campus_id`),
  ADD KEY `fk_jury_program` (`program_id`),
  ADD KEY `fk_jury_president` (`president_id`),
  ADD KEY `fk_jury_secretary` (`secretary_id`),
  ADD KEY `fk_jury_pv` (`pv_document_id`);

--
-- Index pour la table `jury_decisions`
--
ALTER TABLE `jury_decisions`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_jury_student` (`jury_id`,`student_id`),
  ADD KEY `idx_jd_student` (`student_id`),
  ADD KEY `fk_jd_result` (`year_result_id`);

--
-- Index pour la table `jury_members`
--
ALTER TABLE `jury_members`
  ADD PRIMARY KEY (`jury_id`,`user_id`),
  ADD KEY `idx_jm_user` (`user_id`);

--
-- Index pour la table `leave_requests`
--
ALTER TABLE `leave_requests`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_leave_user_dates` (`user_id`,`start_date`,`end_date`),
  ADD KEY `idx_leave_status` (`status`),
  ADD KEY `fk_leave_type` (`leave_type_id`),
  ADD KEY `fk_leave_approver` (`approved_by`);

--
-- Index pour la table `leave_types`
--
ALTER TABLE `leave_types`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_leave_code` (`code`);

--
-- Index pour la table `library_fines`
--
ALTER TABLE `library_fines`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_lf_student_status` (`student_id`,`status`),
  ADD KEY `idx_lf_user_status` (`user_id`,`status`),
  ADD KEY `idx_lf_loan` (`loan_id`),
  ADD KEY `fk_lf_handler` (`handled_by`);

--
-- Index pour la table `library_visits`
--
ALTER TABLE `library_visits`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_lv_campus_date` (`campus_id`,`entered_at`),
  ADD KEY `fk_lv_student` (`student_id`),
  ADD KEY `fk_lv_user` (`user_id`);

--
-- Index pour la table `loan_policies`
--
ALTER TABLE `loan_policies`
  ADD PRIMARY KEY (`borrower_type`);

--
-- Index pour la table `login_logs`
--
ALTER TABLE `login_logs`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_ll_user` (`user_id`),
  ADD KEY `idx_ll_created` (`created_at`);

--
-- Index pour la table `messages`
--
ALTER TABLE `messages`
  ADD PRIMARY KEY (`id`),
  ADD KEY `parent_id` (`parent_id`),
  ADD KEY `idx_msg_recipient` (`recipient_id`,`is_read`),
  ADD KEY `idx_msg_sender` (`sender_id`);

--
-- Index pour la table `notifications`
--
ALTER TABLE `notifications`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_notif_user` (`user_id`,`is_read`);

--
-- Index pour la table `parent_students`
--
ALTER TABLE `parent_students`
  ADD PRIMARY KEY (`parent_user_id`,`student_id`),
  ADD KEY `idx_ps_student` (`student_id`);

--
-- Index pour la table `password_resets`
--
ALTER TABLE `password_resets`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_pr_email` (`email`);

--
-- Index pour la table `payments`
--
ALTER TABLE `payments`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `reference` (`reference`),
  ADD UNIQUE KEY `uk_payment_txn` (`transaction_ref`),
  ADD KEY `received_by` (`received_by`),
  ADD KEY `idx_payments_invoice` (`invoice_id`),
  ADD KEY `idx_payments_date` (`paid_at`),
  ADD KEY `idx_payments_cash` (`cash_register_id`);

--
-- Index pour la table `payroll_periods`
--
ALTER TABLE `payroll_periods`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_payroll_month` (`period_month`),
  ADD KEY `fk_period_creator` (`created_by`);

--
-- Index pour la table `payroll_rules`
--
ALTER TABLE `payroll_rules`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_payroll_rule_code` (`code`);

--
-- Index pour la table `payroll_tax_brackets`
--
ALTER TABLE `payroll_tax_brackets`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_bracket_rule` (`rule_id`,`from_amount`);

--
-- Index pour la table `payslips`
--
ALTER TABLE `payslips`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_payslip` (`period_id`,`user_id`),
  ADD KEY `idx_payslip_user` (`user_id`),
  ADD KEY `fk_payslip_contract` (`contract_id`);

--
-- Index pour la table `payslip_items`
--
ALTER TABLE `payslip_items`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_item_payslip` (`payslip_id`),
  ADD KEY `fk_item_rule` (`rule_id`);

--
-- Index pour la table `permissions`
--
ALTER TABLE `permissions`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `slug` (`slug`);

--
-- Index pour la table `programs`
--
ALTER TABLE `programs`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `code` (`code`),
  ADD KEY `department_id` (`department_id`);

--
-- Index pour la table `roles`
--
ALTER TABLE `roles`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `slug` (`slug`);

--
-- Index pour la table `role_permissions`
--
ALTER TABLE `role_permissions`
  ADD PRIMARY KEY (`role_id`,`permission_id`),
  ADD KEY `permission_id` (`permission_id`);

--
-- Index pour la table `rooms`
--
ALTER TABLE `rooms`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_room` (`campus_id`,`code`);

--
-- Index pour la table `scholarships`
--
ALTER TABLE `scholarships`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `academic_year_id` (`academic_year_id`),
  ADD KEY `approved_by` (`approved_by`);

--
-- Index pour la table `semesters`
--
ALTER TABLE `semesters`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_semester_rank` (`academic_year_id`,`rank_no`),
  ADD KEY `academic_year_id` (`academic_year_id`);

--
-- Index pour la table `semester_results`
--
ALTER TABLE `semester_results`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_semester_result` (`student_id`,`academic_year_id`,`semester_rank`,`session_no`),
  ADD KEY `idx_sr_year` (`academic_year_id`);

--
-- Index pour la table `sequences`
--
ALTER TABLE `sequences`
  ADD PRIMARY KEY (`name`);

--
-- Index pour la table `services`
--
ALTER TABLE `services`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_service_code` (`code`),
  ADD KEY `fk_service_campus` (`campus_id`),
  ADD KEY `fk_service_head` (`head_id`);

--
-- Index pour la table `settings`
--
ALTER TABLE `settings`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `key_name` (`key_name`);

--
-- Index pour la table `staff_appraisals`
--
ALTER TABLE `staff_appraisals`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_appraisal` (`user_id`,`academic_year_id`),
  ADD KEY `fk_ap_year` (`academic_year_id`),
  ADD KEY `fk_ap_evaluator` (`evaluator_id`);

--
-- Index pour la table `staff_attendance`
--
ALTER TABLE `staff_attendance`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_staff_attendance` (`user_id`,`work_date`),
  ADD KEY `idx_sa_date` (`work_date`),
  ADD KEY `fk_sa_recorder` (`recorded_by`);

--
-- Index pour la table `staff_contracts`
--
ALTER TABLE `staff_contracts`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_contract_user_status` (`user_id`,`status`),
  ADD KEY `idx_contract_end` (`end_date`),
  ADD KEY `fk_contract_document` (`document_id`);

--
-- Index pour la table `staff_documents`
--
ALTER TABLE `staff_documents`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_sdoc_user` (`user_id`),
  ADD KEY `fk_sdoc_document` (`document_id`);

--
-- Index pour la table `staff_profiles`
--
ALTER TABLE `staff_profiles`
  ADD PRIMARY KEY (`user_id`),
  ADD UNIQUE KEY `uk_staff_employee_no` (`employee_no`),
  ADD UNIQUE KEY `uk_staff_national_id` (`national_id`),
  ADD KEY `idx_staff_category_status` (`staff_category`,`employment_status`),
  ADD KEY `idx_staff_service` (`service_id`),
  ADD KEY `idx_staff_department` (`department_id`),
  ADD KEY `idx_staff_campus` (`campus_id`),
  ADD KEY `fk_staff_jobtitle` (`job_title_id`);

--
-- Index pour la table `staff_sanctions`
--
ALTER TABLE `staff_sanctions`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_sanction_user` (`user_id`),
  ADD KEY `fk_sanction_decider` (`decided_by`),
  ADD KEY `fk_sanction_document` (`document_id`);

--
-- Index pour la table `staff_trainings`
--
ALTER TABLE `staff_trainings`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_training_user` (`user_id`),
  ADD KEY `fk_training_document` (`certificate_document_id`);

--
-- Index pour la table `students`
--
ALTER TABLE `students`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `matricule` (`matricule`),
  ADD UNIQUE KEY `uk_students_national_id` (`national_id`),
  ADD KEY `user_id` (`user_id`),
  ADD KEY `idx_students_campus` (`campus_id`),
  ADD KEY `idx_students_program` (`program_id`),
  ADD KEY `idx_students_status` (`status`),
  ADD KEY `idx_students_entry_year` (`entry_academic_year_id`),
  ADD KEY `fk_students_admission` (`admission_id`);

--
-- Index pour la table `student_cards`
--
ALTER TABLE `student_cards`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_card_number` (`card_number`),
  ADD KEY `idx_card_student_year` (`student_id`,`academic_year_id`),
  ADD KEY `fk_card_year` (`academic_year_id`),
  ADD KEY `fk_card_issuer` (`issued_by`);

--
-- Index pour la table `student_transfers`
--
ALTER TABLE `student_transfers`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_id` (`student_id`),
  ADD KEY `from_campus_id` (`from_campus_id`),
  ADD KEY `to_campus_id` (`to_campus_id`);

--
-- Index pour la table `syllabus`
--
ALTER TABLE `syllabus`
  ADD PRIMARY KEY (`id`),
  ADD KEY `course_id` (`course_id`),
  ADD KEY `updated_by` (`updated_by`);

--
-- Index pour la table `teacher_profiles`
--
ALTER TABLE `teacher_profiles`
  ADD PRIMARY KEY (`user_id`),
  ADD KEY `idx_tp_department` (`department_id`);

--
-- Index pour la table `teaching_units`
--
ALTER TABLE `teaching_units`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_unit_code` (`code`),
  ADD KEY `idx_unit_program_level` (`program_id`,`level`,`semester_rank`);

--
-- Index pour la table `theses`
--
ALTER TABLE `theses`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_thesis_student` (`student_id`),
  ADD KEY `idx_thesis_supervisor` (`supervisor_id`),
  ADD KEY `fk_thesis_year` (`academic_year_id`),
  ADD KEY `fk_thesis_cosupervisor` (`co_supervisor_id`),
  ADD KEY `fk_thesis_room` (`defense_room_id`),
  ADD KEY `fk_thesis_document` (`document_id`);

--
-- Index pour la table `thesis_jury_members`
--
ALTER TABLE `thesis_jury_members`
  ADD PRIMARY KEY (`thesis_id`,`user_id`),
  ADD KEY `idx_tjm_user` (`user_id`);

--
-- Index pour la table `timetables`
--
ALTER TABLE `timetables`
  ADD PRIMARY KEY (`id`),
  ADD KEY `course_id` (`course_id`),
  ADD KEY `campus_id` (`campus_id`),
  ADD KEY `semester_id` (`semester_id`),
  ADD KEY `idx_tt_conflict` (`room_id`,`day_of_week`,`start_time`,`end_time`),
  ADD KEY `idx_tt_teacher` (`teacher_id`,`day_of_week`,`start_time`,`end_time`);

--
-- Index pour la table `unit_results`
--
ALTER TABLE `unit_results`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_unit_result` (`student_id`,`unit_id`,`academic_year_id`,`session_no`),
  ADD KEY `idx_ur_unit` (`unit_id`),
  ADD KEY `idx_ur_year` (`academic_year_id`);

--
-- Index pour la table `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uuid` (`uuid`),
  ADD UNIQUE KEY `user_name` (`user_name`),
  ADD UNIQUE KEY `email` (`email`),
  ADD KEY `idx_users_category` (`category`),
  ADD KEY `idx_users_campus` (`campus_id`),
  ADD KEY `idx_users_role` (`role_id`);

--
-- Index pour la table `year_results`
--
ALTER TABLE `year_results`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uk_year_result` (`student_id`,`academic_year_id`,`session_no`),
  ADD KEY `idx_yr_program` (`program_id`,`level`),
  ADD KEY `fk_yr_year` (`academic_year_id`);

--
-- AUTO_INCREMENT pour les tables déchargées
--

--
-- AUTO_INCREMENT pour la table `academic_calendar`
--
ALTER TABLE `academic_calendar`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `academic_years`
--
ALTER TABLE `academic_years`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT pour la table `activity_logs`
--
ALTER TABLE `activity_logs`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `admin_activity_logs`
--
ALTER TABLE `admin_activity_logs`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `admin_users`
--
ALTER TABLE `admin_users`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT pour la table `admission_applications`
--
ALTER TABLE `admission_applications`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `alerts`
--
ALTER TABLE `alerts`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `announcements`
--
ALTER TABLE `announcements`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `attendance`
--
ALTER TABLE `attendance`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `books`
--
ALTER TABLE `books`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `book_acquisitions`
--
ALTER TABLE `book_acquisitions`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `book_copies`
--
ALTER TABLE `book_copies`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `book_loans`
--
ALTER TABLE `book_loans`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `book_reservations`
--
ALTER TABLE `book_reservations`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `campuses`
--
ALTER TABLE `campuses`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT pour la table `cash_operations`
--
ALTER TABLE `cash_operations`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `cash_register`
--
ALTER TABLE `cash_register`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `class_sessions`
--
ALTER TABLE `class_sessions`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `courses`
--
ALTER TABLE `courses`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `course_assignments`
--
ALTER TABLE `course_assignments`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `course_results`
--
ALTER TABLE `course_results`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `departments`
--
ALTER TABLE `departments`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `device_tokens`
--
ALTER TABLE `device_tokens`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `documents`
--
ALTER TABLE `documents`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `document_requirements`
--
ALTER TABLE `document_requirements`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `document_types`
--
ALTER TABLE `document_types`
  MODIFY `id` smallint(5) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=20;

--
-- AUTO_INCREMENT pour la table `enrollments`
--
ALTER TABLE `enrollments`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `enrollment_documents`
--
ALTER TABLE `enrollment_documents`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `evaluations`
--
ALTER TABLE `evaluations`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `exam_schedules`
--
ALTER TABLE `exam_schedules`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `faculties`
--
ALTER TABLE `faculties`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `fee_structures`
--
ALTER TABLE `fee_structures`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `grades`
--
ALTER TABLE `grades`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `grade_appeals`
--
ALTER TABLE `grade_appeals`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `grade_history`
--
ALTER TABLE `grade_history`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `grade_mentions`
--
ALTER TABLE `grade_mentions`
  MODIFY `id` tinyint(3) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `internships`
--
ALTER TABLE `internships`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `invoices`
--
ALTER TABLE `invoices`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `invoice_installments`
--
ALTER TABLE `invoice_installments`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `job_titles`
--
ALTER TABLE `job_titles`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=20;

--
-- AUTO_INCREMENT pour la table `juries`
--
ALTER TABLE `juries`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `jury_decisions`
--
ALTER TABLE `jury_decisions`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `leave_requests`
--
ALTER TABLE `leave_requests`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `leave_types`
--
ALTER TABLE `leave_types`
  MODIFY `id` smallint(5) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT pour la table `library_fines`
--
ALTER TABLE `library_fines`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `library_visits`
--
ALTER TABLE `library_visits`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `login_logs`
--
ALTER TABLE `login_logs`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `messages`
--
ALTER TABLE `messages`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `notifications`
--
ALTER TABLE `notifications`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `password_resets`
--
ALTER TABLE `password_resets`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `payments`
--
ALTER TABLE `payments`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `payroll_periods`
--
ALTER TABLE `payroll_periods`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `payroll_rules`
--
ALTER TABLE `payroll_rules`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT pour la table `payroll_tax_brackets`
--
ALTER TABLE `payroll_tax_brackets`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `payslips`
--
ALTER TABLE `payslips`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `payslip_items`
--
ALTER TABLE `payslip_items`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `permissions`
--
ALTER TABLE `permissions`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=104;

--
-- AUTO_INCREMENT pour la table `programs`
--
ALTER TABLE `programs`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `roles`
--
ALTER TABLE `roles`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=19;

--
-- AUTO_INCREMENT pour la table `rooms`
--
ALTER TABLE `rooms`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `scholarships`
--
ALTER TABLE `scholarships`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `semesters`
--
ALTER TABLE `semesters`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `semester_results`
--
ALTER TABLE `semester_results`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `services`
--
ALTER TABLE `services`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=10;

--
-- AUTO_INCREMENT pour la table `settings`
--
ALTER TABLE `settings`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=19;

--
-- AUTO_INCREMENT pour la table `staff_appraisals`
--
ALTER TABLE `staff_appraisals`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `staff_attendance`
--
ALTER TABLE `staff_attendance`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `staff_contracts`
--
ALTER TABLE `staff_contracts`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `staff_documents`
--
ALTER TABLE `staff_documents`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `staff_sanctions`
--
ALTER TABLE `staff_sanctions`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `staff_trainings`
--
ALTER TABLE `staff_trainings`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `students`
--
ALTER TABLE `students`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `student_cards`
--
ALTER TABLE `student_cards`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `student_transfers`
--
ALTER TABLE `student_transfers`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `syllabus`
--
ALTER TABLE `syllabus`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `teaching_units`
--
ALTER TABLE `teaching_units`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `theses`
--
ALTER TABLE `theses`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `timetables`
--
ALTER TABLE `timetables`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `unit_results`
--
ALTER TABLE `unit_results`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT pour la table `users`
--
ALTER TABLE `users`
  MODIFY `id` int(10) UNSIGNED NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT pour la table `year_results`
--
ALTER TABLE `year_results`
  MODIFY `id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Contraintes pour les tables déchargées
--

--
-- Contraintes pour la table `academic_calendar`
--
ALTER TABLE `academic_calendar`
  ADD CONSTRAINT `fk_cal_campus` FOREIGN KEY (`campus_id`) REFERENCES `campuses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_cal_creator` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_cal_year` FOREIGN KEY (`academic_year_id`) REFERENCES `academic_years` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `activity_logs`
--
ALTER TABLE `activity_logs`
  ADD CONSTRAINT `activity_logs_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `admin_activity_logs`
--
ALTER TABLE `admin_activity_logs`
  ADD CONSTRAINT `fk_aal_admin` FOREIGN KEY (`admin_user_id`) REFERENCES `admin_users` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `admin_users`
--
ALTER TABLE `admin_users`
  ADD CONSTRAINT `fk_admin_campus` FOREIGN KEY (`campus_id`) REFERENCES `campuses` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_admin_shadow_user` FOREIGN KEY (`shadow_user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `admission_applications`
--
ALTER TABLE `admission_applications`
  ADD CONSTRAINT `fk_adm_campus` FOREIGN KEY (`campus_id`) REFERENCES `campuses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_adm_program` FOREIGN KEY (`program_id`) REFERENCES `programs` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_adm_reviewer` FOREIGN KEY (`reviewed_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_adm_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `alerts`
--
ALTER TABLE `alerts`
  ADD CONSTRAINT `alerts_ibfk_1` FOREIGN KEY (`target_user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `alerts_ibfk_2` FOREIGN KEY (`campus_id`) REFERENCES `campuses` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `announcements`
--
ALTER TABLE `announcements`
  ADD CONSTRAINT `announcements_ibfk_1` FOREIGN KEY (`campus_id`) REFERENCES `campuses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `announcements_ibfk_2` FOREIGN KEY (`program_id`) REFERENCES `programs` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `announcements_ibfk_3` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `attendance`
--
ALTER TABLE `attendance`
  ADD CONSTRAINT `fk_att_recorder` FOREIGN KEY (`recorded_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_att_session` FOREIGN KEY (`class_session_id`) REFERENCES `class_sessions` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_att_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `books`
--
ALTER TABLE `books`
  ADD CONSTRAINT `books_ibfk_1` FOREIGN KEY (`campus_id`) REFERENCES `campuses` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_books_department` FOREIGN KEY (`department_id`) REFERENCES `departments` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `book_acquisitions`
--
ALTER TABLE `book_acquisitions`
  ADD CONSTRAINT `fk_acq_book` FOREIGN KEY (`book_id`) REFERENCES `books` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_acq_user` FOREIGN KEY (`received_by`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `book_copies`
--
ALTER TABLE `book_copies`
  ADD CONSTRAINT `fk_copy_book` FOREIGN KEY (`book_id`) REFERENCES `books` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `book_loans`
--
ALTER TABLE `book_loans`
  ADD CONSTRAINT `book_loans_ibfk_1` FOREIGN KEY (`book_id`) REFERENCES `books` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `book_loans_ibfk_2` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `book_loans_ibfk_3` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `book_loans_ibfk_4` FOREIGN KEY (`issued_by`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_loans_copy` FOREIGN KEY (`copy_id`) REFERENCES `book_copies` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `book_reservations`
--
ALTER TABLE `book_reservations`
  ADD CONSTRAINT `fk_res_book` FOREIGN KEY (`book_id`) REFERENCES `books` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_res_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_res_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `campuses`
--
ALTER TABLE `campuses`
  ADD CONSTRAINT `fk_campuses_director` FOREIGN KEY (`director_id`) REFERENCES `users` (`id`) ON DELETE SET NULL ON UPDATE CASCADE;

--
-- Contraintes pour la table `cash_operations`
--
ALTER TABLE `cash_operations`
  ADD CONSTRAINT `cash_operations_ibfk_1` FOREIGN KEY (`cash_register_id`) REFERENCES `cash_register` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `cash_operations_ibfk_2` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `cash_register`
--
ALTER TABLE `cash_register`
  ADD CONSTRAINT `cash_register_ibfk_1` FOREIGN KEY (`campus_id`) REFERENCES `campuses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `cash_register_ibfk_2` FOREIGN KEY (`opened_by`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `cash_register_ibfk_3` FOREIGN KEY (`closed_by`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `class_sessions`
--
ALTER TABLE `class_sessions`
  ADD CONSTRAINT `fk_cs_campus` FOREIGN KEY (`campus_id`) REFERENCES `campuses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_cs_course` FOREIGN KEY (`course_id`) REFERENCES `courses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_cs_room` FOREIGN KEY (`room_id`) REFERENCES `rooms` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_cs_syllabus` FOREIGN KEY (`syllabus_id`) REFERENCES `syllabus` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_cs_teacher` FOREIGN KEY (`teacher_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_cs_timetable` FOREIGN KEY (`timetable_id`) REFERENCES `timetables` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_cs_validator` FOREIGN KEY (`validated_by`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `courses`
--
ALTER TABLE `courses`
  ADD CONSTRAINT `courses_ibfk_1` FOREIGN KEY (`program_id`) REFERENCES `programs` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `courses_ibfk_2` FOREIGN KEY (`semester_id`) REFERENCES `semesters` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_courses_unit` FOREIGN KEY (`unit_id`) REFERENCES `teaching_units` (`id`) ON DELETE NO ACTION ON UPDATE CASCADE;

--
-- Contraintes pour la table `course_assignments`
--
ALTER TABLE `course_assignments`
  ADD CONSTRAINT `course_assignments_ibfk_1` FOREIGN KEY (`course_id`) REFERENCES `courses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `course_assignments_ibfk_2` FOREIGN KEY (`teacher_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `course_assignments_ibfk_3` FOREIGN KEY (`academic_year_id`) REFERENCES `academic_years` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `course_assignments_ibfk_4` FOREIGN KEY (`campus_id`) REFERENCES `campuses` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `course_results`
--
ALTER TABLE `course_results`
  ADD CONSTRAINT `course_results_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `course_results_ibfk_2` FOREIGN KEY (`course_id`) REFERENCES `courses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `course_results_ibfk_3` FOREIGN KEY (`academic_year_id`) REFERENCES `academic_years` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `course_results_ibfk_4` FOREIGN KEY (`semester_id`) REFERENCES `semesters` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `departments`
--
ALTER TABLE `departments`
  ADD CONSTRAINT `departments_ibfk_1` FOREIGN KEY (`faculty_id`) REFERENCES `faculties` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `departments_ibfk_2` FOREIGN KEY (`head_id`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `device_tokens`
--
ALTER TABLE `device_tokens`
  ADD CONSTRAINT `device_tokens_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `documents`
--
ALTER TABLE `documents`
  ADD CONSTRAINT `documents_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `documents_ibfk_2` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `documents_ibfk_3` FOREIGN KEY (`issued_by`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `document_requirements`
--
ALTER TABLE `document_requirements`
  ADD CONSTRAINT `fk_req_doctype` FOREIGN KEY (`document_type_id`) REFERENCES `document_types` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `enrollments`
--
ALTER TABLE `enrollments`
  ADD CONSTRAINT `enrollments_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `enrollments_ibfk_2` FOREIGN KEY (`program_id`) REFERENCES `programs` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `enrollments_ibfk_3` FOREIGN KEY (`academic_year_id`) REFERENCES `academic_years` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `enrollments_ibfk_4` FOREIGN KEY (`campus_id`) REFERENCES `campuses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `enrollments_ibfk_5` FOREIGN KEY (`validated_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_enroll_waiver_by` FOREIGN KEY (`documents_waiver_by`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `enrollment_documents`
--
ALTER TABLE `enrollment_documents`
  ADD CONSTRAINT `fk_ed_admission` FOREIGN KEY (`admission_id`) REFERENCES `admission_applications` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_ed_doctype` FOREIGN KEY (`document_type_id`) REFERENCES `document_types` (`id`) ON DELETE NO ACTION,
  ADD CONSTRAINT `fk_ed_document` FOREIGN KEY (`document_id`) REFERENCES `documents` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_ed_enrollment` FOREIGN KEY (`enrollment_id`) REFERENCES `enrollments` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_ed_received_by` FOREIGN KEY (`received_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_ed_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_ed_verified_by` FOREIGN KEY (`verified_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_ed_year` FOREIGN KEY (`academic_year_id`) REFERENCES `academic_years` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `evaluations`
--
ALTER TABLE `evaluations`
  ADD CONSTRAINT `evaluations_ibfk_1` FOREIGN KEY (`course_id`) REFERENCES `courses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `evaluations_ibfk_2` FOREIGN KEY (`teacher_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_eval_year` FOREIGN KEY (`academic_year_id`) REFERENCES `academic_years` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `exam_schedules`
--
ALTER TABLE `exam_schedules`
  ADD CONSTRAINT `fk_exam_campus` FOREIGN KEY (`campus_id`) REFERENCES `campuses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_exam_course` FOREIGN KEY (`course_id`) REFERENCES `courses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_exam_eval` FOREIGN KEY (`evaluation_id`) REFERENCES `evaluations` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_exam_room` FOREIGN KEY (`room_id`) REFERENCES `rooms` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_exam_semester` FOREIGN KEY (`semester_id`) REFERENCES `semesters` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_exam_supervisor` FOREIGN KEY (`supervisor_id`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `faculties`
--
ALTER TABLE `faculties`
  ADD CONSTRAINT `faculties_ibfk_1` FOREIGN KEY (`dean_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `faculties_ibfk_2` FOREIGN KEY (`campus_id`) REFERENCES `campuses` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `fee_structures`
--
ALTER TABLE `fee_structures`
  ADD CONSTRAINT `fee_structures_ibfk_1` FOREIGN KEY (`program_id`) REFERENCES `programs` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fee_structures_ibfk_2` FOREIGN KEY (`academic_year_id`) REFERENCES `academic_years` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `grades`
--
ALTER TABLE `grades`
  ADD CONSTRAINT `grades_ibfk_1` FOREIGN KEY (`evaluation_id`) REFERENCES `evaluations` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `grades_ibfk_2` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `grades_ibfk_3` FOREIGN KEY (`entered_by`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `grade_appeals`
--
ALTER TABLE `grade_appeals`
  ADD CONSTRAINT `fk_appeal_eval` FOREIGN KEY (`evaluation_id`) REFERENCES `evaluations` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_appeal_handler` FOREIGN KEY (`handled_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_appeal_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `internships`
--
ALTER TABLE `internships`
  ADD CONSTRAINT `fk_intern_report` FOREIGN KEY (`report_document_id`) REFERENCES `documents` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_intern_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_intern_supervisor` FOREIGN KEY (`academic_supervisor_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_intern_year` FOREIGN KEY (`academic_year_id`) REFERENCES `academic_years` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `invoices`
--
ALTER TABLE `invoices`
  ADD CONSTRAINT `invoices_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `invoices_ibfk_2` FOREIGN KEY (`academic_year_id`) REFERENCES `academic_years` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `invoices_ibfk_3` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `invoice_installments`
--
ALTER TABLE `invoice_installments`
  ADD CONSTRAINT `fk_inst_invoice` FOREIGN KEY (`invoice_id`) REFERENCES `invoices` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `juries`
--
ALTER TABLE `juries`
  ADD CONSTRAINT `fk_jury_campus` FOREIGN KEY (`campus_id`) REFERENCES `campuses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_jury_president` FOREIGN KEY (`president_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_jury_program` FOREIGN KEY (`program_id`) REFERENCES `programs` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_jury_pv` FOREIGN KEY (`pv_document_id`) REFERENCES `documents` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_jury_secretary` FOREIGN KEY (`secretary_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_jury_year` FOREIGN KEY (`academic_year_id`) REFERENCES `academic_years` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `jury_decisions`
--
ALTER TABLE `jury_decisions`
  ADD CONSTRAINT `fk_jd_jury` FOREIGN KEY (`jury_id`) REFERENCES `juries` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_jd_result` FOREIGN KEY (`year_result_id`) REFERENCES `year_results` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_jd_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `jury_members`
--
ALTER TABLE `jury_members`
  ADD CONSTRAINT `fk_jm_jury` FOREIGN KEY (`jury_id`) REFERENCES `juries` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_jm_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `leave_requests`
--
ALTER TABLE `leave_requests`
  ADD CONSTRAINT `fk_leave_approver` FOREIGN KEY (`approved_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_leave_type` FOREIGN KEY (`leave_type_id`) REFERENCES `leave_types` (`id`),
  ADD CONSTRAINT `fk_leave_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `library_fines`
--
ALTER TABLE `library_fines`
  ADD CONSTRAINT `fk_lf_handler` FOREIGN KEY (`handled_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_lf_loan` FOREIGN KEY (`loan_id`) REFERENCES `book_loans` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_lf_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_lf_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `library_visits`
--
ALTER TABLE `library_visits`
  ADD CONSTRAINT `fk_lv_campus` FOREIGN KEY (`campus_id`) REFERENCES `campuses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_lv_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_lv_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `login_logs`
--
ALTER TABLE `login_logs`
  ADD CONSTRAINT `login_logs_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `messages`
--
ALTER TABLE `messages`
  ADD CONSTRAINT `messages_ibfk_1` FOREIGN KEY (`sender_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `messages_ibfk_2` FOREIGN KEY (`recipient_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `messages_ibfk_3` FOREIGN KEY (`parent_id`) REFERENCES `messages` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `notifications`
--
ALTER TABLE `notifications`
  ADD CONSTRAINT `notifications_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `parent_students`
--
ALTER TABLE `parent_students`
  ADD CONSTRAINT `fk_ps_parent` FOREIGN KEY (`parent_user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_ps_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `payments`
--
ALTER TABLE `payments`
  ADD CONSTRAINT `fk_payments_cash` FOREIGN KEY (`cash_register_id`) REFERENCES `cash_register` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `payments_ibfk_1` FOREIGN KEY (`invoice_id`) REFERENCES `invoices` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `payments_ibfk_2` FOREIGN KEY (`received_by`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `payroll_periods`
--
ALTER TABLE `payroll_periods`
  ADD CONSTRAINT `fk_period_creator` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `payroll_tax_brackets`
--
ALTER TABLE `payroll_tax_brackets`
  ADD CONSTRAINT `fk_bracket_rule` FOREIGN KEY (`rule_id`) REFERENCES `payroll_rules` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `payslips`
--
ALTER TABLE `payslips`
  ADD CONSTRAINT `fk_payslip_contract` FOREIGN KEY (`contract_id`) REFERENCES `staff_contracts` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_payslip_period` FOREIGN KEY (`period_id`) REFERENCES `payroll_periods` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_payslip_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `payslip_items`
--
ALTER TABLE `payslip_items`
  ADD CONSTRAINT `fk_item_payslip` FOREIGN KEY (`payslip_id`) REFERENCES `payslips` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_item_rule` FOREIGN KEY (`rule_id`) REFERENCES `payroll_rules` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `programs`
--
ALTER TABLE `programs`
  ADD CONSTRAINT `programs_ibfk_1` FOREIGN KEY (`department_id`) REFERENCES `departments` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `role_permissions`
--
ALTER TABLE `role_permissions`
  ADD CONSTRAINT `role_permissions_ibfk_1` FOREIGN KEY (`role_id`) REFERENCES `roles` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `role_permissions_ibfk_2` FOREIGN KEY (`permission_id`) REFERENCES `permissions` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `rooms`
--
ALTER TABLE `rooms`
  ADD CONSTRAINT `rooms_ibfk_1` FOREIGN KEY (`campus_id`) REFERENCES `campuses` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `scholarships`
--
ALTER TABLE `scholarships`
  ADD CONSTRAINT `scholarships_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `scholarships_ibfk_2` FOREIGN KEY (`academic_year_id`) REFERENCES `academic_years` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `scholarships_ibfk_3` FOREIGN KEY (`approved_by`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `semesters`
--
ALTER TABLE `semesters`
  ADD CONSTRAINT `semesters_ibfk_1` FOREIGN KEY (`academic_year_id`) REFERENCES `academic_years` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `semester_results`
--
ALTER TABLE `semester_results`
  ADD CONSTRAINT `fk_sr_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_sr_year` FOREIGN KEY (`academic_year_id`) REFERENCES `academic_years` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `services`
--
ALTER TABLE `services`
  ADD CONSTRAINT `fk_service_campus` FOREIGN KEY (`campus_id`) REFERENCES `campuses` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_service_head` FOREIGN KEY (`head_id`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `staff_appraisals`
--
ALTER TABLE `staff_appraisals`
  ADD CONSTRAINT `fk_ap_evaluator` FOREIGN KEY (`evaluator_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_ap_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_ap_year` FOREIGN KEY (`academic_year_id`) REFERENCES `academic_years` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `staff_attendance`
--
ALTER TABLE `staff_attendance`
  ADD CONSTRAINT `fk_sa_recorder` FOREIGN KEY (`recorded_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_sa_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `staff_contracts`
--
ALTER TABLE `staff_contracts`
  ADD CONSTRAINT `fk_contract_document` FOREIGN KEY (`document_id`) REFERENCES `documents` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_contract_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `staff_documents`
--
ALTER TABLE `staff_documents`
  ADD CONSTRAINT `fk_sdoc_document` FOREIGN KEY (`document_id`) REFERENCES `documents` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_sdoc_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `staff_profiles`
--
ALTER TABLE `staff_profiles`
  ADD CONSTRAINT `fk_staff_campus` FOREIGN KEY (`campus_id`) REFERENCES `campuses` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_staff_department` FOREIGN KEY (`department_id`) REFERENCES `departments` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_staff_jobtitle` FOREIGN KEY (`job_title_id`) REFERENCES `job_titles` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_staff_service` FOREIGN KEY (`service_id`) REFERENCES `services` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_staff_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `staff_sanctions`
--
ALTER TABLE `staff_sanctions`
  ADD CONSTRAINT `fk_sanction_decider` FOREIGN KEY (`decided_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_sanction_document` FOREIGN KEY (`document_id`) REFERENCES `documents` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_sanction_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `staff_trainings`
--
ALTER TABLE `staff_trainings`
  ADD CONSTRAINT `fk_training_document` FOREIGN KEY (`certificate_document_id`) REFERENCES `documents` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_training_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `students`
--
ALTER TABLE `students`
  ADD CONSTRAINT `fk_students_admission` FOREIGN KEY (`admission_id`) REFERENCES `admission_applications` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_students_entry_year` FOREIGN KEY (`entry_academic_year_id`) REFERENCES `academic_years` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `students_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `students_ibfk_2` FOREIGN KEY (`campus_id`) REFERENCES `campuses` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `students_ibfk_3` FOREIGN KEY (`program_id`) REFERENCES `programs` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `student_cards`
--
ALTER TABLE `student_cards`
  ADD CONSTRAINT `fk_card_issuer` FOREIGN KEY (`issued_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_card_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_card_year` FOREIGN KEY (`academic_year_id`) REFERENCES `academic_years` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `student_transfers`
--
ALTER TABLE `student_transfers`
  ADD CONSTRAINT `student_transfers_ibfk_1` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `student_transfers_ibfk_2` FOREIGN KEY (`from_campus_id`) REFERENCES `campuses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `student_transfers_ibfk_3` FOREIGN KEY (`to_campus_id`) REFERENCES `campuses` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `syllabus`
--
ALTER TABLE `syllabus`
  ADD CONSTRAINT `syllabus_ibfk_1` FOREIGN KEY (`course_id`) REFERENCES `courses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `syllabus_ibfk_2` FOREIGN KEY (`updated_by`) REFERENCES `users` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `teacher_profiles`
--
ALTER TABLE `teacher_profiles`
  ADD CONSTRAINT `fk_tp_department` FOREIGN KEY (`department_id`) REFERENCES `departments` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_tp_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `teaching_units`
--
ALTER TABLE `teaching_units`
  ADD CONSTRAINT `fk_unit_program` FOREIGN KEY (`program_id`) REFERENCES `programs` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `theses`
--
ALTER TABLE `theses`
  ADD CONSTRAINT `fk_thesis_cosupervisor` FOREIGN KEY (`co_supervisor_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_thesis_document` FOREIGN KEY (`document_id`) REFERENCES `documents` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_thesis_room` FOREIGN KEY (`defense_room_id`) REFERENCES `rooms` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_thesis_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_thesis_supervisor` FOREIGN KEY (`supervisor_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  ADD CONSTRAINT `fk_thesis_year` FOREIGN KEY (`academic_year_id`) REFERENCES `academic_years` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `thesis_jury_members`
--
ALTER TABLE `thesis_jury_members`
  ADD CONSTRAINT `fk_tjm_thesis` FOREIGN KEY (`thesis_id`) REFERENCES `theses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_tjm_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `timetables`
--
ALTER TABLE `timetables`
  ADD CONSTRAINT `timetables_ibfk_1` FOREIGN KEY (`course_id`) REFERENCES `courses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `timetables_ibfk_2` FOREIGN KEY (`teacher_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `timetables_ibfk_3` FOREIGN KEY (`room_id`) REFERENCES `rooms` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `timetables_ibfk_4` FOREIGN KEY (`campus_id`) REFERENCES `campuses` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `timetables_ibfk_5` FOREIGN KEY (`semester_id`) REFERENCES `semesters` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `unit_results`
--
ALTER TABLE `unit_results`
  ADD CONSTRAINT `fk_ur_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_ur_unit` FOREIGN KEY (`unit_id`) REFERENCES `teaching_units` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_ur_year` FOREIGN KEY (`academic_year_id`) REFERENCES `academic_years` (`id`) ON DELETE CASCADE;

--
-- Contraintes pour la table `users`
--
ALTER TABLE `users`
  ADD CONSTRAINT `fk_users_role` FOREIGN KEY (`role_id`) REFERENCES `roles` (`id`) ON DELETE NO ACTION ON UPDATE CASCADE,
  ADD CONSTRAINT `users_ibfk_1` FOREIGN KEY (`campus_id`) REFERENCES `campuses` (`id`) ON DELETE SET NULL;

--
-- Contraintes pour la table `year_results`
--
ALTER TABLE `year_results`
  ADD CONSTRAINT `fk_yr_program` FOREIGN KEY (`program_id`) REFERENCES `programs` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_yr_student` FOREIGN KEY (`student_id`) REFERENCES `students` (`id`) ON DELETE CASCADE,
  ADD CONSTRAINT `fk_yr_year` FOREIGN KEY (`academic_year_id`) REFERENCES `academic_years` (`id`) ON DELETE CASCADE;

DELIMITER $$
--
-- Évènements
--
CREATE DEFINER=`root`@`localhost` EVENT `ev_mark_late_loans` ON SCHEDULE EVERY 1 DAY STARTS '2026-10-24 01:00:00' ON COMPLETION NOT PRESERVE ENABLE DO UPDATE `book_loans` SET `status`='retard'
   WHERE `status`='en_cours' AND `due_date` < CURRENT_DATE$$

CREATE DEFINER=`root`@`localhost` EVENT `ev_purge_password_resets` ON SCHEDULE EVERY 1 DAY STARTS '2026-10-24 02:00:00' ON COMPLETION NOT PRESERVE ENABLE DO DELETE FROM `password_resets` WHERE `expires_at` < NOW()$$

CREATE DEFINER=`root`@`localhost` EVENT `ev_expire_reservations` ON SCHEDULE EVERY 1 HOUR STARTS '2026-10-23 13:34:44' ON COMPLETION NOT PRESERVE ENABLE DO UPDATE `book_reservations` SET `status`='expirée'
   WHERE `status`='disponible' AND `expires_at` < NOW()$$

DELIMITER ;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
