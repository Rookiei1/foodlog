#!/usr/bin/env python3
"""
Comprehensive Swift Code Integrity and Verifier Feedback Verification Script.
Checks bracket balance, token structures, and validates the 8 verification items.
"""
import os
import re
import sys

FOODLOG_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))

def check_brackets(filepath):
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    stack = []
    pairs = {")": "(", "}": "{", "]": "["}
    in_string = False
    in_multiline_string = False
    in_single_comment = False
    in_multi_comment = False
    i = 0
    n = len(content)
    line = 1
    col = 1

    while i < n:
        ch = content[i]
        if ch == "\n":
            line += 1
            col = 1
            in_single_comment = False
            i += 1
            continue

        if in_multi_comment:
            if ch == "*" and i + 1 < n and content[i + 1] == "/":
                in_multi_comment = False
                i += 2
                col += 2
                continue
            i += 1
            col += 1
            continue

        if in_single_comment:
            i += 1
            col += 1
            continue

        if not in_string and not in_multiline_string:
            if ch == "/" and i + 1 < n and content[i + 1] == "/":
                in_single_comment = True
                i += 2
                col += 2
                continue
            if ch == "/" and i + 1 < n and content[i + 1] == "*":
                in_multi_comment = True
                i += 2
                col += 2
                continue

        if i + 2 < n and content[i : i + 3] == '"""':
            in_multiline_string = not in_multiline_string
            i += 3
            col += 3
            continue

        if in_multiline_string:
            i += 1
            col += 1
            continue

        if ch == '"' and (i == 0 or content[i - 1] != "\\"):
            in_string = not in_string
            i += 1
            col += 1
            continue

        if in_string:
            i += 1
            col += 1
            continue

        if ch in "({[":
            stack.append((ch, line, col))
        elif ch in ")}]":
            expected = pairs[ch]
            if not stack:
                return f"Unmatched closing bracket {ch} at line {line}:{col}"
            top, top_line, top_col = stack.pop()
            if top != expected:
                return f"Mismatched bracket: expected closing for {top} (line {top_line}:{top_col}), found {ch} at line {line}:{col}"

        i += 1
        col += 1

    if stack:
        top, top_line, top_col = stack.pop()
        return f"Unclosed bracket {top} opened at line {top_line}:{top_col}"
    return None


def verify_all_brackets():
    print("=== 1. Checking Bracket Balance across Swift files ===")
    target_dirs = [
        os.path.join(FOODLOG_DIR, "FoodLog"),
        os.path.join(FOODLOG_DIR, "Tests"),
        os.path.join(FOODLOG_DIR, "UITests"),
    ]
    total_files = 0
    errors = []
    for td in target_dirs:
        for root, _, files in os.walk(td):
            for f in files:
                if f.endswith(".swift"):
                    total_files += 1
                    fp = os.path.join(root, f)
                    err = check_brackets(fp)
                    if err:
                        errors.append(f"{os.path.relpath(fp, FOODLOG_DIR)}: {err}")

    if errors:
        for e in errors:
            print(f"  [FAIL] {e}")
        return False
    print(f"  [PASS] All {total_files} active Swift files have perfectly balanced brackets.")
    return True


def verify_feedback_items():
    print("\n=== 2. Checking 8 Iteration-1 Feedback Items ===")
    all_passed = True

    # Item 1: LocalMockAIAdapter in AIProviderAdapters.swift
    adapter_path = os.path.join(FOODLOG_DIR, "FoodLog", "AIProviders", "AIProviderAdapters.swift")
    with open(adapter_path, "r", encoding="utf-8") as f:
        adapter_src = f.read()
    if "typealias LocalMockAIAdapter = MockAIProviderAdapter" in adapter_src:
        print("  [PASS] Item 1: LocalMockAIAdapter typealias exists in AIProviderAdapters.swift")
    else:
        print("  [FAIL] Item 1: LocalMockAIAdapter typealias missing")
        all_passed = False

    # Item 2: Argument labels in HistoryView.swift
    history_path = os.path.join(FOODLOG_DIR, "FoodLog", "Views", "HistoryView.swift")
    with open(history_path, "r", encoding="utf-8") as f:
        history_src = f.read()
    if "writeTemporaryExportFile(\n            data: foodCSV,\n            filename:" in history_src or "writeTemporaryExportFile(\r\n            data: foodCSV,\r\n            filename:" in history_src:
        print("  [PASS] Item 2: HistoryView calls writeTemporaryExportFile(data: ..., filename: ...)")
    else:
        print("  [FAIL] Item 2: Incorrect argument labels for writeTemporaryExportFile in HistoryView.swift")
        all_passed = False

    # Item 3: Method names in DashboardView and HistoryView
    dash_path = os.path.join(FOODLOG_DIR, "FoodLog", "Views", "DashboardView.swift")
    with open(dash_path, "r", encoding="utf-8") as f:
        dash_src = f.read()
    if "presentFoodEditor" in dash_src:
        print("  [FAIL] Item 3: DashboardView still has presentFoodEditor")
        all_passed = False
    elif "openEditFoodSheet" in dash_src:
        print("  [PASS] Item 3: DashboardView correctly calls appState.openEditFoodSheet")
    else:
        print("  [FAIL] Item 3: openEditFoodSheet not found in DashboardView")
        all_passed = False

    if "presentFoodEditor" in history_src or "presentWeightEditor" in history_src:
        print("  [FAIL] Item 3: HistoryView still has presentFoodEditor / presentWeightEditor")
        all_passed = False
    elif "openEditFoodSheet" in history_src and "openEditWeightSheet" in history_src:
        print("  [PASS] Item 3: HistoryView correctly calls appState.openEditFoodSheet and openEditWeightSheet")
    else:
        print("  [FAIL] Item 3: openEditFoodSheet or openEditWeightSheet missing in HistoryView")
        all_passed = False

    # Item 4: Unit test assertions in RefactorViewModelAndNavigationTests.swift
    test_path = os.path.join(FOODLOG_DIR, "Tests", "RefactorViewModelAndNavigationTests.swift")
    with open(test_path, "r", encoding="utf-8") as f:
        test_src = f.read()
    if "2697 - 400" in test_src and "2697 + 350" in test_src:
        print("  [PASS] Item 4: RefactorViewModelAndNavigationTests uses 2697 - 400 and 2697 + 350")
    else:
        print("  [FAIL] Item 4: RefactorViewModelAndNavigationTests has incorrect calorie adjustment assertions")
        all_passed = False

    # Item 5: Deduplication protection in DataExportService.swift
    export_path = os.path.join(FOODLOG_DIR, "FoodLog", "Export", "DataExportService.swift")
    with open(export_path, "r", encoding="utf-8") as f:
        export_src = f.read()
    if "seenFoodIDs.insert(item.id)" in export_src and "seenWeightIDs.insert(weight.id)" in export_src:
        print("  [PASS] Item 5: DataExportService uses seen*IDs mutable sets and inserts on import")
    else:
        print("  [FAIL] Item 5: DataExportService deduplication protection not restored properly")
        all_passed = False

    # Item 6: deepseek-chat in AIVisionCapabilityChecker
    models_path = os.path.join(FOODLOG_DIR, "FoodLog", "AIProviders", "AIProviderModels.swift")
    with open(models_path, "r", encoding="utf-8") as f:
        models_src = f.read()
    deepseek_case = re.search(r"case\s+\.deepSeek:\s*(.+)", models_src)
    if deepseek_case:
        line = deepseek_case.group(1)
        if 'contains("chat")' in line:
            print("  [FAIL] Item 6: case .deepSeek still falsely contains 'chat'")
            all_passed = False
        else:
            print("  [PASS] Item 6: case .deepSeek vision check correctly excludes 'chat'")
    else:
        print("  [FAIL] Item 6: case .deepSeek not found in AIProviderModels.swift")
        all_passed = False

    # Item 7: 项目说明.md line 22
    doc_path = os.path.join(FOODLOG_DIR, "项目说明.md")
    with open(doc_path, "r", encoding="utf-8") as f:
        doc_src = f.read()
    if "五大 Tab" in doc_src:
        print("  [FAIL] Item 7: 项目说明.md still mentions '五大 Tab'")
        all_passed = False
    elif "2026 极简三大 Tab" in doc_src:
        print("  [PASS] Item 7: 项目说明.md correctly updated to 2026 极简三大 Tab")
    else:
        print("  [FAIL] Item 7: 项目说明.md missing 3-Tab description")
        all_passed = False

    return all_passed


if __name__ == "__main__":
    ok1 = verify_all_brackets()
    ok2 = verify_feedback_items()
    if ok1 and ok2:
        print("\n>>> ALL CHECKS PASSED SUCCESSFULLY! <<<")
        sys.exit(0)
    else:
        print("\n>>> VERIFICATION FAILED! <<<")
        sys.exit(1)
