# MoonECAT Project Workflow

本目录承接原 AI 任务清单的拆分结果，现作为任务拆解与维护的主入口。

原则：

- 本目录按主题拆分，便于分别维护“基线/路线图”“里程碑”“参考矩阵”“风险与依赖”“主线 backlog”。
- 原始单体 AI 任务清单已下线，后续更新直接落在对应拆分文件中。
- 如果需要总览，请以本 README 和各主题文件组合浏览，而不是恢复单一大文件。

## 文件索引

- [01_baseline_and_roadmap.md](../project_workflow/01_baseline_and_roadmap.md)：原文引言、`0`、`0.1`、`0.2`
- [02_productization_tracks.md](../project_workflow/02_productization_tracks.md)：原文 `0.3`、`0.4`、`0.5`、`0.6`、`0.7`
- [03_milestones_m1_m4.md](../project_workflow/03_milestones_m1_m4.md)：原文 `1` 与 `2` 中 `M1-M4`
- [04_milestones_m5_m8.md](../project_workflow/04_milestones_m5_m8.md)：原文 `2` 中 `M5-M8`
- [05_reference_matrix_and_closure.md](../project_workflow/05_reference_matrix_and_closure.md)：原文 `3` 与 `8`
- [06_parallel_workflows_dependencies_risks.md](../project_workflow/06_parallel_workflows_dependencies_risks.md)：原文 `4`、`5`、`6`
- [07_backlog_and_commit_process.md](../project_workflow/07_backlog_and_commit_process.md)：原文 `9`、`10`

## 章节覆盖关系

| 原文章节 | 拆分文件 |
|---|---|
| 引言 / 0 / 0.1 / 0.2 | [01_baseline_and_roadmap.md](../project_workflow/01_baseline_and_roadmap.md) |
| 0.3 / 0.4 / 0.5 / 0.6 / 0.7 | [02_productization_tracks.md](../project_workflow/02_productization_tracks.md) |
| 1 / 2(M1-M4) | [03_milestones_m1_m4.md](../project_workflow/03_milestones_m1_m4.md) |
| 2(M5-M8) | [04_milestones_m5_m8.md](../project_workflow/04_milestones_m5_m8.md) |
| 3 / 8 | [05_reference_matrix_and_closure.md](../project_workflow/05_reference_matrix_and_closure.md) |
| 4 / 5 / 6 | [06_parallel_workflows_dependencies_risks.md](../project_workflow/06_parallel_workflows_dependencies_risks.md) |
| 9 / 10 | [07_backlog_and_commit_process.md](../project_workflow/07_backlog_and_commit_process.md) |

## 维护建议

- 与实现强绑定的内容，优先更新参考矩阵、backlog、验收与风险文件。
- 引用仓内其他文档时，注意本目录相对路径统一使用 `../`。
- 如果后续需要继续细分，建议优先按“产品主线”拆，而不是按日期或提交批次拆。
