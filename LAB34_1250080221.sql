-- Câu 1.1: Tạo view vw_course_summary - thông tin tổng quan môn học
CREATE OR REPLACE VIEW vw_course_summary AS
SELECT co.MaMon,
       co.TenMon,
       co.HocPhi,
       COUNT(DISTINCT cl.MaLopID) AS so_lop,
       COUNT(e.MaSV) AS tong_sv
FROM MON_HOC co
LEFT JOIN LOP_HOC cl ON co.MaMon = cl.MaMon
LEFT JOIN DANG_KY_HOC e ON cl.MaLopID = e.MaLopID
GROUP BY co.MaMon, co.TenMon, co.HocPhi
ORDER BY tong_sv DESC;

-- Kiem tra view:
SELECT * FROM vw_course_summary;
-- Câu 1.2: Tạo view vw_student_status - thông tin sinh viên và tình trạng học tập
CREATE OR REPLACE VIEW vw_student_status AS
SELECT s.MaSV,
       s.Ho || ' ' || s.Ten AS ho_ten,
       COUNT(e.MaLopID) AS so_lop_hoc,
       NVL(SUM(co.HocPhi), 0) AS tong_hoc_phi,
       ROUND(AVG(e.DiemTongKet), 2) AS diem_tb
FROM SINH_VIEN s
JOIN DANG_KY_HOC e ON s.MaSV = e.MaSV
JOIN LOP_HOC cl ON e.MaLopID = cl.MaLopID
JOIN MON_HOC co ON cl.MaMon = co.MaMon
GROUP BY s.MaSV, s.Ho, s.Ten
HAVING COUNT(e.MaLopID) >= 1
ORDER BY s.MaSV;

SELECT * FROM vw_student_status;
-- Câu 1.3: Tạo view vw_class_availability - lớp học còn chỗ trống
CREATE OR REPLACE VIEW vw_class_availability AS
SELECT cl.MaLopID,
       cl.MaMon,
       co.TenMon,
       i.Ho || ' ' || i.Ten AS ten_giao_vien,
       cl.SiSoToiDa,
       COUNT(e.MaSV) AS so_da_dk,
       cl.SiSoToiDa - COUNT(e.MaSV) AS cho_trong,
       CASE
           WHEN cl.SiSoToiDa - COUNT(e.MaSV) > 0 THEN 'Con cho'
           ELSE 'Het cho'
       END AS trang_thai
FROM LOP_HOC cl
JOIN MON_HOC co ON cl.MaMon = co.MaMon
JOIN GIAO_VIEN i ON cl.MaGV = i.MaGV
LEFT JOIN DANG_KY_HOC e ON cl.MaLopID = e.MaLopID
GROUP BY cl.MaLopID, cl.MaMon, co.TenMon, i.Ho, i.Ten, cl.SiSoToiDa
HAVING cl.SiSoToiDa - COUNT(e.MaSV) > 0
ORDER BY cl.MaLopID;

SELECT * FROM vw_class_availability;
-- Câu 1.4: Tạo view vw_top_courses - chỉ đọc, top 5 môn được đăng ký nhiều nhất
CREATE OR REPLACE VIEW vw_top_courses AS
SELECT MaMon, TenMon, HocPhi, tong_dk, hang
FROM (
    SELECT co.MaMon,
           co.TenMon,
           co.HocPhi,
           COUNT(e.MaSV) AS tong_dk,
           RANK() OVER (ORDER BY COUNT(e.MaSV) DESC) AS hang
    FROM MON_HOC co
    LEFT JOIN LOP_HOC cl ON co.MaMon = cl.MaMon
    LEFT JOIN DANG_KY_HOC e ON cl.MaLopID = e.MaLopID
    GROUP BY co.MaMon, co.TenMon, co.HocPhi
)
WHERE hang <= 5
ORDER BY hang
WITH READ ONLY;

SELECT * FROM vw_top_courses;

-- Thu INSERT vao view nay (se bao loi ORA-42399):
INSERT INTO vw_top_courses (MaMon, TenMon, HocPhi)
VALUES (999, 'Test', 100);
-- Oracle bao: ORA-42399: cannot perform a DML operation on a read-only view
-- Câu 1.5: Tạo view vw_pending_enrollment với WITH CHECK OPTION và kiểm tra
CREATE OR REPLACE VIEW vw_pending_enrollment AS
SELECT MaSV, MaLopID, NgayDK, DiemTongKet,
       NguoiTao, NgayTao, NguoiSua, NgaySua
FROM DANG_KY_HOC
WHERE DiemTongKet IS NULL
WITH CHECK OPTION;

SELECT * FROM vw_pending_enrollment;

-- INSERT 1: FinalGrade = NULL -> THANH CONG (thoa dieu kien WHERE)
INSERT INTO vw_pending_enrollment
(MaSV, MaLopID, NgayDK, DiemTongKet,
       NguoiTao, NgayTao, NguoiSua, NgaySua)
VALUES (999, 1, SYSDATE, USER, SYSDATE, USER, SYSDATE);
-- INSERT 2: FinalGrade = 85 -> LOI ORA-01402 (vi pham WITH CHECK OPTION)
INSERT INTO vw_pending_enrollment
(MaSV, MaLopID, NgayDK, DiemTongKet,
       NguoiTao, NgayTao, NguoiSua, NgaySua)
VALUES (998, 1, SYSDATE, 85, USER, SYSDATE, USER, SYSDATE);
-- ORA-01402: view WITH CHECK OPTION where-clause violation
-- Câu 2.1: Thủ tục enroll_student - đăng ký sinh viên vào lớp học
CREATE OR REPLACE PROCEDURE enroll_student
(p_studentid IN NUMBER,
 p_classid IN NUMBER)
IS
    v_check NUMBER;
    v_capacity NUMBER;
    v_enrolled NUMBER;
BEGIN
    -- DK1: Sinh vien phai ton tai
    SELECT COUNT(*) INTO v_check FROM SINH_VIEN WHERE MaSV = p_studentid;
    IF v_check = 0 THEN
        DBMS_OUTPUT.PUT_LINE('[LOI] Sinh vien ' || p_studentid || ' khong ton tai!');
        RETURN;
    END IF;

    -- DK2: Lop hoc phai ton tai
    SELECT COUNT(*) INTO v_check FROM LOP_HOC WHERE MaLopID = p_classid;
    IF v_check = 0 THEN
        DBMS_OUTPUT.PUT_LINE('[LOI] Lop hoc ' || p_classid || ' khong ton tai!');
        RETURN;
    END IF;

    -- DK3: Kiem tra con cho trong
    SELECT SiSoToiDa INTO v_capacity FROM LOP_HOC WHERE MaLopID = p_classid;
    SELECT COUNT(*) INTO v_enrolled FROM DANG_KY_HOC WHERE MaLopID = p_classid;
    IF v_enrolled >= v_capacity THEN
        DBMS_OUTPUT.PUT_LINE('[LOI] Lop' || p_classid || ' da day! (' || v_enrolled || '/' || v_capacity || ')');
        RETURN;
    END IF;

    -- DK4: Sinh vien chua dang ky lop nay
    SELECT COUNT(*) INTO v_check FROM DANG_KY_HOC 
    WHERE MaSV = p_studentid AND MaLopID = p_classid;
    IF v_check > 0 THEN
        DBMS_OUTPUT.PUT_LINE('[LOI] Sinh vien da dang ky lop nay roi!');
        RETURN;
    END IF;

    -- DK5: Sinh vien chua qua 3 lop
    SELECT COUNT(*) INTO v_check FROM DANG_KY_HOC WHERE MaSV = p_studentid;
    IF v_check >= 3 THEN
        DBMS_OUTPUT.PUT_LINE('[LOI] Sinh vien da dang ky du 3 lop!');
        RETURN;
    END IF;

    -- Tat ca OK: INSERT
    INSERT INTO DANG_KY_HOC
    (MaSV, MaLopID, NgayDK, NguoiTao, NgayTao, NguoiSua, NgaySua)
    VALUES
    (p_studentid, p_classid, SYSDATE, USER, SYSDATE, USER, SYSDATE);
    
    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] Dang ky thanh cong! SV' || p_studentid || ' -> Lop' || p_classid);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('[LOI HE THONG] ' || SQLERRM);
END enroll_student;
/

-- Kiem tra:
BEGIN
enroll_student(101, 5); -- Hop le
enroll_student(999, 5); -- SV khong ton tai
enroll_student(101, 999); -- Lop khong ton tai
END;
/

-- 1. Gọi thủ tục cho sinh viên 1002 đăng ký vào lớp 3
BEGIN
    enroll_student(1002, 3); 
END;
/

-- 2. Lệnh kiểm tra kết quả trong CSDL
SELECT * FROM DANG_KY_HOC WHERE MaSV = 1002;
--Câu 2.2: Thủ tục update_final_grade - cập nhật điểm tổng kết
CREATE OR REPLACE PROCEDURE update_final_grade
(p_studentid IN NUMBER,
 p_classid IN NUMBER,
 p_grade IN NUMBER)
IS
    v_check NUMBER;
    v_old_grade NUMBER;
BEGIN
    -- Kiem tra diem hop le
    IF p_grade < 0 OR p_grade > 100 THEN
        DBMS_OUTPUT.PUT_LINE('[LOI] Diem khong hop le! Phai tu 0 den 100.');
        RETURN;
    END IF;

    -- Kiem tra cap (StudentID, ClassID) ton tai trong ENROLLMENT
    SELECT COUNT(*) INTO v_check FROM DANG_KY_HOC
    WHERE MaSV = p_studentid AND MaLopID = p_classid;
    IF v_check = 0 THEN
        DBMS_OUTPUT.PUT_LINE('[LOI] Sinh vien chua dang ky lop nay!');
        RETURN;
    END IF;

    -- Luu diem cu
    SELECT DiemTongKet INTO v_old_grade FROM DANG_KY_HOC
    WHERE MaSV = p_studentid AND MaLopID = p_classid;

    -- Cap nhat ENROLLMENT
    UPDATE DANG_KY_HOC
    SET DiemTongKet = p_grade,
        NguoiSua = USER, NgaySua = SYSDATE
    WHERE MaSV = p_studentid AND MaLopID = p_classid;

    -- Dong bo sang bang GRADE bang MERGE INTO
    MERGE INTO DIEM_SO g
    USING (SELECT p_studentid AS sid, p_classid AS cid FROM DUAL) src
    ON (g.MaSV = src.sid AND g.MaLopID = src.cid)
    WHEN MATCHED THEN
        UPDATE SET g.Diem = p_grade,
                   g.NguoiSua = USER, g.NgaySua = SYSDATE
    WHEN NOT MATCHED THEN
        INSERT (MaSV, MaLopID, Diem, NguoiTao, NgayTao, NguoiSua, NgaySua)
        VALUES (p_studentid, p_classid, p_grade, USER, SYSDATE, USER, SYSDATE);

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] Da cap nhat diem SV ' || p_studentid
                      || ' lop' || p_classid
                      || ': Cu=' || NVL(TO_CHAR(v_old_grade),'NULL')
                      || ' -> Moi=' || p_grade);
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('[LOI] ' || SQLERRM);
END update_final_grade;
SELECT * FROM update_final_grade

-- 1. Cập nhật điểm cho SV 1001 ở lớp 1 thành 88 điểm
BEGIN
    update_final_grade(1001, 1, 88);
END;
/

-- 2. Kiểm tra xem điểm đã được lưu vào bảng DANG_KY_HOC chưa
SELECT MaSV, MaLopID, DiemTongKet FROM DANG_KY_HOC WHERE MaSV = 1001 AND MaLopID = 1;

-- 3. Kiểm tra xem điểm đã đồng bộ sang bảng DIEM_SO chưa
SELECT * FROM DIEM_SO WHERE MaSV = 1001 AND MaLopID = 1;
--Câu 2.3: Thủ tục transfer_student - chuyển lớp cho sinh viên
CREATE OR REPLACE PROCEDURE transfer_student
(p_studentid IN NUMBER,
 p_old_classid IN NUMBER,
 p_new_classid IN NUMBER)
IS
    v_check NUMBER;
    v_capacity NUMBER;
    v_enrolled NUMBER;
BEGIN
    -- DK1: Sinh vien dang hoc o lop cu
    SELECT COUNT(*) INTO v_check FROM DANG_KY_HOC
    WHERE MaSV = p_studentid AND MaLopID = p_old_classid;
    IF v_check = 0 THEN
        DBMS_OUTPUT.PUT_LINE('[LOI] Sinh vien khong dang hoc lop' || p_old_classid);
        RETURN;
    END IF;

    -- DK2: Lop moi con cho trong
    SELECT SiSoToiDa INTO v_capacity FROM LOP_HOC WHERE MaLopID = p_new_classid;
    SELECT COUNT(*) INTO v_enrolled FROM DANG_KY_HOC WHERE MaLopID = p_new_classid;
    IF v_enrolled >= v_capacity THEN
        DBMS_OUTPUT.PUT_LINE('[LOI] Lop moi ' || p_new_classid || ' da day!');
        RETURN;
    END IF;

    -- DK3: Sinh vien chua dang ky lop moi
    SELECT COUNT(*) INTO v_check FROM DANG_KY_HOC
    WHERE MaSV = p_studentid AND MaLopID = p_new_classid;
    IF v_check > 0 THEN
        DBMS_OUTPUT.PUT_LINE('[LOI] Sinh vien da o trong lop moi roi!');
        RETURN;
    END IF;

    -- Tat ca OK: thuc hien chuyen lop
    SAVEPOINT sp_truoc_chuyen;

    -- Buoc 1: Xoa khoi lop cu
    DELETE FROM DANG_KY_HOC
    WHERE MaSV = p_studentid AND MaLopID = p_old_classid;
    SAVEPOINT sp_sau_xoa;

    -- Buoc 2: Them vao lop moi
    INSERT INTO DANG_KY_HOC
    (MaSV, MaLopID, NgayDK, NguoiTao, NgayTao, NguoiSua, NgaySua)
    VALUES
    (p_studentid, p_new_classid, SYSDATE, USER, SYSDATE, USER, SYSDATE);

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] Da chuyen SV ' || p_studentid
                      || ' tu lop' || p_old_classid
                      || ' sang lop' || p_new_classid);
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO sp_truoc_chuyen;
        DBMS_OUTPUT.PUT_LINE('[LOI] Chuyen lop that bai: ' || SQLERRM);
        DBMS_OUTPUT.PUT_LINE('Da rollback ve trang thai ban dau.');
END transfer_student;
/

-- 1. Giả sử chuyển SV 1001 từ lớp 1 sang lớp 4
BEGIN
    transfer_student(1001, 1, 4);
END;
/

-- 2. Kiểm tra danh sách các lớp sinh viên 1001 đang học
SELECT * FROM DANG_KY_HOC WHERE MaSV = 1001;
--Câu 2.4: Thủ tục report_class_detail — in báo cáo chi tiết lớp học
CREATE OR REPLACE PROCEDURE report_class_detail
(p_classid IN NUMBER)
IS
    v_check NUMBER;
    v_course VARCHAR2(50);
    v_courseno NUMBER;
    v_gv VARCHAR2(50);
    v_loc VARCHAR2(50);
    v_cap NUMBER;
    v_stt NUMBER := 0;
    v_tong NUMBER := 0;
    v_sum_d NUMBER := 0;
    v_co_d NUMBER := 0;
    v_grade_txt VARCHAR2(15);
BEGIN
    -- Kiem tra lop ton tai
    SELECT COUNT(*) INTO v_check FROM LOP_HOC WHERE MaLopID = p_classid;
    IF v_check = 0 THEN
        DBMS_OUTPUT.PUT_LINE('Lop hoc ' || p_classid || ' khong ton tai!');
        RETURN;
    END IF;

    -- Lay thong tin lop
    SELECT co.TenMon, co.MaMon,
           i.Ho || ' ' || i.Ten,
           cl.PhongHoc, cl.SiSoToiDa
    INTO v_course, v_courseno, v_gv, v_loc, v_cap
    FROM LOP_HOC cl
    JOIN MON_HOC co ON cl.MaMon = co.MaMon
    JOIN GIAO_VIEN i ON cl.MaGV = i.MaGV
    WHERE cl.MaLopID = p_classid;

    -- In header bao cao
    DBMS_OUTPUT.PUT_LINE('BAO CAO LOP HOC: ' || p_classid || ' =');
    DBMS_OUTPUT.PUT_LINE('Mon hoc : ' || v_courseno || ' - ' || v_course);
    DBMS_OUTPUT.PUT_LINE('Giao vien: ' || v_gv);
    DBMS_OUTPUT.PUT_LINE('Phong hoc: ' || NVL(v_loc, 'Chua xep phong'));
    DBMS_OUTPUT.PUT_LINE('Suc chua: ' || v_cap || ' cho');
    DBMS_OUTPUT.PUT_LINE(RPAD('-',50,'-'));
    DBMS_OUTPUT.PUT_LINE('DANH SACH SINH VIEN:');
    DBMS_OUTPUT.PUT_LINE(RPAD('STT',4) || ' | ' || RPAD('Ho Ten',20)
                      || '|' || LPAD('Diem TK',8) || ' | Xep loai');
    DBMS_OUTPUT.PUT_LINE(RPAD('-',50,'-'));

    -- Duyet danh sach sinh vien
    FOR rec IN (
        SELECT s.Ho || ' ' || s.Ten AS ho_ten,
               e.DiemTongKet
        FROM DANG_KY_HOC e
        JOIN SINH_VIEN s ON e.MaSV = s.MaSV
        WHERE e.MaLopID = p_classid
        ORDER BY s.Ho, s.Ten
    ) LOOP
        v_stt := v_stt + 1;
        v_tong := v_tong + 1;

        -- Xep loai
        IF rec.DiemTongKet IS NULL THEN
            v_grade_txt := 'Chua co diem';
        ELSIF rec.DiemTongKet >= 90 THEN
            v_grade_txt := 'A';
            v_sum_d := v_sum_d + rec.DiemTongKet; v_co_d := v_co_d + 1;
        ELSIF rec.DiemTongKet >= 80 THEN
            v_grade_txt := 'B';
            v_sum_d := v_sum_d + rec.DiemTongKet; v_co_d := v_co_d + 1;
        ELSIF rec.DiemTongKet >= 70 THEN
            v_grade_txt := 'C';
            v_sum_d := v_sum_d + rec.DiemTongKet; v_co_d := v_co_d + 1;
        ELSIF rec.DiemTongKet >= 50 THEN
            v_grade_txt := 'D';
            v_sum_d := v_sum_d + rec.DiemTongKet; v_co_d := v_co_d + 1;
        ELSE
            v_grade_txt := 'F';
            v_sum_d := v_sum_d + rec.DiemTongKet; v_co_d := v_co_d + 1;
        END IF;

        DBMS_OUTPUT.PUT_LINE(
            LPAD(v_stt,3) || ' | '
            || RPAD(rec.ho_ten, 20) || '|'
            || LPAD(NVL(TO_CHAR(rec.DiemTongKet), 'NULL'), 7) || ' | '
            || v_grade_txt
        );
    END LOOP;

    -- In footer bao cao
    DBMS_OUTPUT.PUT_LINE(RPAD('-',50,'-'));
    DBMS_OUTPUT.PUT_LINE('Tong so sinh vien : ' || v_tong);
    IF v_co_d > 0 THEN
        DBMS_OUTPUT.PUT_LINE('Diem trung binh lop: ' || ROUND(v_sum_d/v_co_d, 2));
    ELSE
        DBMS_OUTPUT.PUT_LINE('Diem trung binh lop: Chua co diem');
    END IF;
END report_class_detail;
/

-- Goi thu tuc:
BEGIN
report_class_detail(1);
END;
/
--Câu 2.5: Thủ tục sync_grade_from_enrollment - đồng bộ điểm từ ENROLLMENT sang GRADE
CREATE OR REPLACE PROCEDURE sync_grade_from_enrollment
IS
    v_check NUMBER;
    v_dem_insert NUMBER := 0;
    v_dem_update NUMBER := 0;
BEGIN
    FOR rec IN (
        SELECT MaSV, MaLopID, DiemTongKet
        FROM DANG_KY_HOC
        WHERE DiemTongKet IS NOT NULL
    ) LOOP
        -- Kiem tra trong GRADE da co chua
        SELECT COUNT(*) INTO v_check FROM DIEM_SO
        WHERE MaSV = rec.MaSV AND MaLopID = rec.MaLopID;

        IF v_check = 0 THEN
            -- Chua co -> INSERT moi
            INSERT INTO DIEM_SO
            (MaSV, MaLopID, Diem, NguoiTao, NgayTao, NguoiSua, NgaySua)
            VALUES
            (rec.MaSV, rec.MaLopID, rec.DiemTongKet, USER, SYSDATE, USER, SYSDATE);
            v_dem_insert := v_dem_insert + 1;
        ELSE
            -- Da co -> UPDATE
            UPDATE DIEM_SO
            SET Diem = rec.DiemTongKet,
                NguoiSua = USER, NgaySua = SYSDATE
            WHERE MaSV = rec.MaSV AND MaLopID = rec.MaLopID;
            v_dem_update := v_dem_update + 1;
        END IF;
    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('[OK] Dong bo hoan tat!');
    DBMS_OUTPUT.PUT_LINE(' So ban ghi INSERT moi : ' || v_dem_insert);
    DBMS_OUTPUT.PUT_LINE(' So ban ghi UPDATE : ' || v_dem_update);
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('[LOI] ' || SQLERRM);
END sync_grade_from_enrollment;
/

BEGIN sync_grade_from_enrollment; 
END; 
/
--BÀI 3 – TRIGGER
--Câu 3.1: Trigger trg_check_capacity - kiểm tra sức chứa khi đăng ký
CREATE OR REPLACE TRIGGER trg_check_capacity
BEFORE INSERT ON DANG_KY_HOC
FOR EACH ROW
DECLARE
    v_capacity NUMBER;
    v_enrolled NUMBER;
BEGIN
    -- Lay suc chua lop hoc
    SELECT SiSoToiDa INTO v_capacity
    FROM LOP_HOC WHERE MaLopID = :NEW.MaLopID;

    -- Dem so SV hien da dang ky
    SELECT COUNT(*) INTO v_enrolled
    FROM DANG_KY_HOC WHERE MaLopID = :NEW.MaLopID;

    -- Tu choi neu lop da day
    IF v_enrolled >= v_capacity THEN
        RAISE_APPLICATION_ERROR(
            -20010,
            'LOI: Lop' || :NEW.MaLopID || ' da day! (' || v_enrolled || '/' || v_capacity || ' cho)'
        );
    END IF;
END trg_check_capacity;
/

-- Kiem tra trigger (dang ky vao lop da day):
INSERT INTO DANG_KY_HOC
(MaSV, MaLopID, NgayDK,
       NguoiTao, NgayTao, NguoiSua, NgaySua)
VALUES (1003, 1, SYSDATE, USER, SYSDATE, USER, SYSDATE);
SELECT * FROM DANG_KY_HOC WHERE MaSV = '1003'
--Câu 3.2: Trigger trg_grade_audit_log - ghi nhật ký thay đổi điểm
CREATE TABLE grade_audit_log (
    log_id NUMBER GENERATED ALWAYS AS IDENTITY,
    MaSV NUMBER(8),
    MaLopID NUMBER(8),
    grade_cu NUMBER(3),
    grade_moi NUMBER(3),
    nguoi_sua VARCHAR2(30),
    thoi_gian DATE
);

CREATE OR REPLACE TRIGGER trg_grade_audit_log
AFTER UPDATE OF DiemTongKet ON DANG_KY_HOC
FOR EACH ROW
BEGIN
    -- Chi ghi log khi diem THUC SU thay doi
    IF (:OLD.DiemTongKet IS NULL AND :NEW.DiemTongKet IS NOT NULL)
    OR (:OLD.DiemTongKet IS NOT NULL AND :NEW.DiemTongKet IS NULL)
    OR (:OLD.DiemTongKet != :NEW.DiemTongKet)
    THEN
        INSERT INTO grade_audit_log
        (MaSV, MaLopID, grade_cu, grade_moi, nguoi_sua, thoi_gian)
        VALUES
        (:OLD.MaSV, :OLD.MaLopID, :OLD.DiemTongKet, :NEW.DiemTongKet, USER, SYSDATE);
    END IF;
END trg_grade_audit_log;
/

-- Kiem tra trigger:
UPDATE DANG_KY_HOC 
SET DiemTongKet = 85
WHERE MaSV = 1001 AND MaLopID = 1;

COMMIT;

-- Xem ket qua log da duoc luu
SELECT * FROM grade_audit_log;
-- Kiem tra: xoa mon co lop (se bao loi ORA-20020 do trigger chan)
DELETE FROM MON_HOC WHERE MaMon = 101; 

-- Kiem tra: xoa mon khong co lop (thanh cong)
-- Lưu ý: Bạn cần chắc chắn môn 999 đã được tạo trước đó (như ví dụ mình đã hướng dẫn ở trên)
DELETE FROM MON_HOC WHERE MaMon = 999; 
ROLLBACK;
--Câu 3.3: Trigger trg_prevent_course_delete - ngăn xóa môn học đang có lớp
CREATE OR REPLACE TRIGGER trg_prevent_course_delete
BEFORE DELETE ON MON_HOC
FOR EACH ROW
DECLARE
    v_so_lop NUMBER;
BEGIN
    SELECT COUNT(*) INTO v_so_lop
    FROM LOP_HOC WHERE MaMon = :OLD.MaMon;

    IF v_so_lop > 0 THEN
        RAISE_APPLICATION_ERROR(
            -20020,
            'Khong the xoa mon hoc ' || :OLD.MaMon ||
            '(' || :OLD.TenMon || ') ' ||
            'vi con' || v_so_lop || ' lop hoc dang ton tai!'
        );
    END IF;
    -- Neu v_so_lop = 0 trigger ket thuc binh thuong, Oracle tien hanh xoa
END trg_prevent_course_delete;
/
--Câu 3.4: Trigger trg_update_grade_summary - cập nhật bảng thống kê tự động
CREATE TABLE class_grade_summary (
    MaLopID NUMBER(8) PRIMARY KEY,
    so_sv NUMBER,
    diem_tb NUMBER(5,2),
    diem_cao_nhat NUMBER(3),
    diem_thap_nhat NUMBER(3),
    cap_nhat_luc DATE
);

CREATE OR REPLACE TRIGGER trg_update_grade_summary
AFTER INSERT OR UPDATE OR DELETE ON DANG_KY_HOC
FOR EACH ROW
DECLARE
    v_classid NUMBER;
    v_so_sv NUMBER;
    v_diem_tb NUMBER;
    v_max_d NUMBER;
    v_min_d NUMBER;
BEGIN
    -- Lay MaLopID dua tren loai su kien
    IF INSERTING OR UPDATING THEN
        v_classid := :NEW.MaLopID;
    ELSE -- DELETING
        v_classid := :OLD.MaLopID;
    END IF;

    -- Tinh lai thong ke cho lop bi anh huong
    SELECT COUNT(DiemTongKet),
           ROUND(AVG(DiemTongKet), 2),
           MAX(DiemTongKet),
           MIN(DiemTongKet)
    INTO v_so_sv, v_diem_tb, v_max_d, v_min_d
    FROM DANG_KY_HOC
    WHERE MaLopID = v_classid AND DiemTongKet IS NOT NULL;

    -- MERGE INTO cap nhat hoac them moi
    MERGE INTO class_grade_summary cgs
    USING (SELECT v_classid AS cid FROM DUAL) src
    ON (cgs.MaLopID = src.cid)
    WHEN MATCHED THEN
        UPDATE SET
            so_sv = v_so_sv,
            diem_tb = v_diem_tb,
            diem_cao_nhat = v_max_d,
            diem_thap_nhat = v_min_d,
            cap_nhat_luc = SYSDATE
    WHEN NOT MATCHED THEN
        INSERT (MaLopID, so_sv, diem_tb, diem_cao_nhat, diem_thap_nhat, cap_nhat_luc)
        VALUES (v_classid, v_so_sv, v_diem_tb, v_max_d, v_min_d, SYSDATE);
END trg_update_grade_summary;
/
-- 1. Kiem tra trigger voi sinh vien 1001 va lop 1: 
UPDATE DANG_KY_HOC 
SET DiemTongKet = 90
WHERE MaSV = 1001 AND MaLopID = 1;
COMMIT;
SELECT * FROM class_grade_summary WHERE MaLopID = 1;
SELECT * FROM  DANG_KY_HOC 
--BÀI 4 - TỔNG HỢP
--Câu 4.1: Hệ thống báo cáo hoàn chỉnh - View + Procedure + Cursor
-- b1
CREATE OR REPLACE VIEW vw_instructor_workload AS
SELECT i.MaGV,
       i.Ho || ' ' || i.Ten AS ho_ten,
       COUNT(DISTINCT cl.MaLopID) AS so_lop,
       COUNT(e.MaSV) AS tong_sv,
       ROUND(AVG(e.DiemTongKet), 2) AS diem_tb_chung,
       CASE
           WHEN COUNT(DISTINCT cl.MaLopID) >= 3 THEN 'Ban nhieu'
           WHEN COUNT(DISTINCT cl.MaLopID) = 2 THEN 'Binh thuong'
           ELSE 'Nhe nhang'
       END AS muc_ban
FROM GIAO_VIEN i
LEFT JOIN LOP_HOC cl ON i.MaGV = cl.MaGV
LEFT JOIN DANG_KY_HOC e ON cl.MaLopID = e.MaLopID
GROUP BY i.MaGV, i.Ho, i.Ten
ORDER BY so_lop DESC;

SELECT * FROM vw_instructor_workload;

-- b2
CREATE OR REPLACE PROCEDURE print_system_report
IS
    v_so_mon NUMBER;
    v_so_lop NUMBER;
    v_so_sv NUMBER;
    v_so_gv NUMBER;
BEGIN
    -- Lay so lieu tong the
    SELECT COUNT(*) INTO v_so_mon FROM MON_HOC;
    SELECT COUNT(*) INTO v_so_lop FROM LOP_HOC;
    SELECT COUNT(*) INTO v_so_sv FROM SINH_VIEN;
    SELECT COUNT(*) INTO v_so_gv FROM GIAO_VIEN;

    -- In header
    DBMS_OUTPUT.PUT_LINE(' BAO CAO TOAN HE THONG QUAN LY KHOA HỌC');
    DBMS_OUTPUT.PUT_LINE('=');
    DBMS_OUTPUT.PUT_LINE('Tong so mon hoc: ' || v_so_mon);
    DBMS_OUTPUT.PUT_LINE('Tong so lop hoc: ' || v_so_lop);
    DBMS_OUTPUT.PUT_LINE('Tong so sinh vien: ' || v_so_sv);
    DBMS_OUTPUT.PUT_LINE('Tong so giao vien: ' || v_so_gv);
    DBMS_OUTPUT.PUT_LINE(RPAD('-',50,'-'));

    -- Phan 1: Thong ke giao vien (dung view vw_instructor_workload)
    DBMS_OUTPUT.PUT_LINE('THONG KE GIAO VIEN:');
    FOR rec IN (SELECT * FROM vw_instructor_workload) LOOP
        DBMS_OUTPUT.PUT_LINE(
            '' || RPAD(rec.ho_ten, 25)
            || '|' || LPAD(rec.so_lop, 2) || ' lop'
            || '|' || LPAD(rec.tong_sv, 3) || ' SV'
            || ' | DTB: ' || NVL(TO_CHAR(rec.diem_tb_chung),'--')
            || ' | ' || rec.muc_ban
        );
    END LOOP;
    DBMS_OUTPUT.PUT_LINE(RPAD('-',50,'-'));

    -- Phan 2: Top 3 mon hoc (dung view vw_top_courses)
    DBMS_OUTPUT.PUT_LINE('TOP 3 MON HOC DUOC DANG KY NHIEU NHAT:');
    FOR rec IN (SELECT * FROM vw_top_courses WHERE hang <= 3) LOOP
        DBMS_OUTPUT.PUT_LINE(
            '' || rec.hang || '.'
            || RPAD(rec.TenMon, 30)
            || '-' || rec.tong_dk || ' luot dang ky'
        );
    END LOOP;
    DBMS_OUTPUT.PUT_LINE('=');
END print_system_report;
/
-- Chay bao cao:
SET SERVEROUTPUT ON SIZE 1000000;
BEGIN print_system_report; END;
/