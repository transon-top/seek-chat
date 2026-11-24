# Dart/Flutter 架构与测试官方最佳实践

> 调研日期：2026-11-24（下文所有来源均为当日访问）
> 来源约束：仅使用官方文档与官方包页面；Context7 只用于定位文档，正文引用一律落到官方 URL。官方文档未表态之处直接标注「官方未表态」，不补造规范。

## 1. 官方最佳实践

### 1.1 分层：UI / logic（domain）/ data

**分层是官方默认要求，但层数按复杂度决定。** 官方 concepts 页写明：

> "Flutter applications should be written in layers... Typically, applications are separated into 2 to 3 layers, depending on complexity."

并定义：UI layer 负责展示与交互；logic layer（domain layer）实现核心业务逻辑，**是可选的**，只在客户端有复杂业务逻辑时需要；data layer 管理数据库、平台插件等数据源（[Common architecture concepts · Layered architecture](https://docs.flutter.dev/app-architecture/concepts)，2026-11-24）。官方同时给出层间通信规则：

> "each layer can only communicate with the layers directly below or above it. The UI layer shouldn't know that the data layer exists, and vice versa."

（[Common architecture concepts · Layered architecture](https://docs.flutter.dev/app-architecture/concepts)，2026-11-24）

**MVVM 是官方推荐的具体形状。** 官方指南把 View 和 ViewModel 放在 UI layer，把 Repository 和 Service 放在 data layer（也就是 MVVM 的 Model）：

> "Views and view models should have a one-to-one relationship."
> "In the simplest terms, a view model manages the UI state and the view displays that state."
> "most of the logic in your Flutter application lives in view models."

（[Guide to app architecture · MVVM / UI layer / View models](https://docs.flutter.dev/app-architecture/guide)，2026-11-24）

View 的职责被限定为展示与转发事件：

> "Views are the primary method of rendering UI, and shouldn't contain any business logic. They should be passed all data they need to render from the view model."
> "All logic related to data should be handled in the view model."

（[Guide to app architecture · Views](https://docs.flutter.dev/app-architecture/guide)，2026-11-24）

官方 recommendations 页把这条升级为 **Strongly recommend**：

> "Do not put logic in widgets." — *Strongly recommend*
> "Logic should be encapsulated in methods on the ViewModel. The only logic a view should contain is: simple if-statements... animation logic... layout logic... simple routing logic."

（[Architecture recommendations · Separation of concerns](https://docs.flutter.dev/app-architecture/recommendations)，2026-11-24）

**Repository / Service 的分工。** 官方指南要求 Repository 作为数据唯一真相源，承担缓存、错误处理、重试、刷新、轮询；Service 是无状态的数据源封装，每个数据源一个 service class：

> "Repositories are the source of the truth for application data, and contain logic that relates to that data..."
> "Repositories handle the business logic associated with services, such as: Caching, Error handling, Retry logic, Refreshing data, Polling services for new data..."
> "Services are in the lowest layer of your application... They're only used to isolate data-loading, and they hold no state."

（[Guide to app architecture · Data layer / Repositories / Services](https://docs.flutter.dev/app-architecture/guide)，2026-11-24）

依赖规则同样明确：

> "Repositories should never be aware of each other. If your application has business logic that needs data from two repositories, you should combine the data in the view model or in the domain layer."
> "A view model can use many repositories to get the data it needs, and a repository can be used by many view models."

（[Guide to app architecture · Data layer](https://docs.flutter.dev/app-architecture/guide)，2026-11-24）

**domain layer 何时值得引入。** 官方 recommendations 把「Use a domain layer」标为 **Conditional**，理由非常具体：

> "A domain layer is only needed if your application has exceeding complex logic that crowds your ViewModels, or if you find yourself repeating logic in ViewModels. In very large apps, use-cases are useful, but in most apps they add unnecessary overhead."

（[Architecture recommendations · Separation of concerns](https://docs.flutter.dev/app-architecture/recommendations)，2026-11-24）

官方指南的 use-case 定义是：use-case 依赖 repository，ViewModel 依赖 use-case 和 repository；use-case 负责把 repository 数据转成 UI 可用的形状：

> "Use-cases are responsible for making interactions between the UI and Data layers simpler and more reusable. They take data from repositories and make it suitable for the UI layer."
> "A good approach is to add use-cases only when needed."

（[Guide to app architecture · Optional: Domain layer / Data access with use-cases](https://docs.flutter.dev/app-architecture/guide)，2026-11-24）

**feature-first vs layer-first。** 官方 case study 的取舍是：data layer 按类型组织（`data/`），UI 按 feature 组织（`ui/`），因为 repository/service 可被多个 feature 复用，而每个 feature 只有一个 view + 一个 view model：

> "The data folder organizes code by type, because repositories and services can be used across different features and by multiple view models. The ui folder organizes code by feature, because each feature has exactly one view and exactly one view model."

（[Architecture case study · Package structure](https://docs.flutter.dev/app-architecture/case-study)，2026-11-24）

**官方文档内部有一处张力，需要如实指出。** recommendations 页说「data layer ... contains most of the business logic in your application」（[Architecture recommendations · Separation of concerns](https://docs.flutter.dev/app-architecture/recommendations)，2026-11-24），而 guide 页说「most of the logic in your Flutter application lives in view models」（[Guide to app architecture · View models](https://docs.flutter.dev/app-architecture/guide)，2026-11-24）。两者并不完全一致。可操作的解读是：**UI state 与 UI logic 归 ViewModel，数据规则、重试、持久化归 data layer（或可选 domain layer）**；争论「哪一层代码行数更多」没有官方答案。

### 1.2 状态管理：Riverpod 3.x

**官方不指定唯一状态管理方案。** Flutter 的 state management 选项页明确：

> "The best choice for your app often depends on the app's complexity, your team's preferences, and the specific problems you need to solve."
> "Depending on the complexity of your app and preferences of your team, you might find adopting a state management package useful."

（[Approaches to state management](https://docs.flutter.dev/data-and-backend/state-mgmt/options)，2026-11-24）

因此下文的 Riverpod 规范只约束「已经选择 Riverpod」之后的做法，不构成 Flutter 官方对 Riverpod 的背书。

**Provider 与 Notifier 的职责。** Riverpod 官方定义 provider 为带缓存的 memoized function：

> "Providers are essentially \"memoized functions\", with sugar on top... providers are functions which will return a cached value when called with the same parameters."

Notifier 负责暴露修改 state 的方法：

> "Notifiers are responsible for exposing ways to modify the state of the provider."
> "Public methods on this class are accessible to consumers using `ref.read(yourProvider.notifier).yourMethod()`."

并且明确逻辑应放在 `build` 而不是 constructor：

> "Do not put logic in the constructor of your notifier."
> "Notifiers should not have a constructor, as `ref` and other properties aren't yet available at that point."
> "Instead, put your logic in the `build` method."

（[Providers · What is a provider? / Creating a provider](https://riverpod.dev/docs/concepts2/providers)，2026-11-24）

**Provider 只用于共享业务状态。** 官方 DO/DON'T 页：

> "AVOID using providers for Ephemeral state." — "Reserve providers for shared business state. For selections, forms, animations, and controllers, use local widget state..."
> "DON'T perform side effects during the initialization of a provider" — "Providers should represent reads, not writes such as form submission."
> "AVOID initializing providers in a widget" — "Providers should initialize themselves... If setup depends on outside factors, trigger it from the relevant action."

（[DO/DON'T](https://riverpod.dev/docs/root/do_dont)，2026-11-24）

**autoDispose / keepAlive / family。** 官方 auto-dispose 页：

> 目的是 "automatically destroy resources associated with a provider when it is no longer used."
> 不用 codegen 时 "you can enable it by using `isAutoDispose: true` when creating the provider"。
> 参数化 provider："When providers receive parameters, it is recommended to enable automatic disposal." 否则 "one state per parameter combination will be created, which can lead to memory leaks."
> `ref.keepAlive` "can keep the state of successful network requests, but not cache failed requests"，并可 "decide when the state stops being automatically disposed".
> 销毁时机：listener 计数归零 → `Ref.onCancel` → 等一帧 → 仍无使用则 `Ref.onDispose`。

（[Automatic disposal · Automatic disposal / When is automatic disposal triggered? / Fine-tuned disposal with ref.keepAlive](https://riverpod.dev/docs/concepts2/auto_dispose)，2026-11-24）

family 页补充：

> "View \"family\" as a Map, where the parameters are the key and the provider's state is the value."
> "Although not strictly required, it is highly advised to enable Automatic disposal when using families."
> "This avoids memory leaks in case the parameter changes and the previous state is no longer needed."

（[Family](https://riverpod.dev/docs/concepts2/family)，2026-11-24）

**provider scoping。** 官方 scoping 页把它限定为「改变 provider 在一小部分应用中的行为」，通过 nested `ProviderContainer` / `ProviderScope` 的 override 实现；适用场景只有三类：页面/Widget 级定制、性能优化、避免逐层传参（family 的替代）。官方同时警告：

> "The scoping feature is highly complex and will likely be reworked in the future to be more ergonomic."

（[Scoping providers · Defining a scoped provider / Dependency sharing](https://riverpod.dev/docs/concepts2/scoping)，2026-11-24）

**测试。** 官方 testing 页要求：

> "Tests should not share state."
> "DO NOT share ProviderContainers between tests."
> "All providers can be mocked by default, without any additional setup."（通过 `ProviderScope` / `ProviderContainer` 的 `overrides`）
> "It is generally discouraged to mock Notifiers." — 推荐改为 mock Notifier 依赖的 abstraction / repository。
> autoDispose provider 在测试中用 `container.listen` 保活，避免 `container.read` 中途丢状态。

（[Testing your providers · Setting up a test / Mocking Notifiers](https://riverpod.dev/docs/how_to/testing)，2026-11-24）

**codegen vs 手写。** 官方明确 codegen 完全可选：

> "When using Riverpod, code generation is completely optional. It is entirely possible to use Riverpod without."
> "Riverpod embraces code generation and recommends using it."
> 但采用条件是："Only if you already use code-generation for other things." 否则 "it is probably not worth it to start using it just for Riverpod." 理由是 generator "currently is still fairly slow"。

（[About code generation · Should I use code generation?](https://riverpod.dev/docs/concepts/about_code_generation)，2026-11-24）

**Riverpod 3.x 的版本相关约束。** 官方 What's new 页列出列出的相关行为：

> 自动重试："Starting 3.0, providers that fail during initialization will automatically retry." 指数退避，默认最多 10 次，从 200ms 起翻倍到 6.4s；默认重试除 `Error` / `ProviderException` 之外的错误。
> 暂停/恢复："Listeners inside widgets that are not visible are now paused." "If a provider is only used by paused providers, it is paused too."
> 异常包装：provider 读取失败会包成 `ProviderException`；disposed 的 `Ref`/`Notifier` 再交互会抛错。
> 测试工具：`ProviderContainer.test` 自动 dispose；`NotifierProvider.overrideWithBuild` 可只覆盖 `build`；`WidgetTester.container`。
> Mutations / offline persistence 仍标注为 experimental。

（[What's new in Riverpod 3.0 · Automatic retry / Pause/Resume support / Provider life-cycle changes / New testing utilities / Mutations (experimental)](https://riverpod.dev/docs/whats_new)，2026-11-24）

**关于 god notifier：官方文档没有给出 notifier 行数或职责数量上限。** 能引用的只有两条间接约束：provider 只承载共享业务状态、不要在 provider 初始化时做 side effect（[DO/DON'T](https://riverpod.dev/docs/root/do_dont)，2026-11-24）。因此「一个 notifier 是否过大」必须用语义所有权与接口深度判断，不能引用官方阈值。

### 1.3 数据层：drift

**DAO 的官方定位是「查询多了就拆」。**

> "Keep your database code modular with DAOs."
> 使用条件："you have a lot of queries, putting them all into one class might become tedious."
> "You can avoid this by extracting some queries into classes that are available from your main database class."

官方 DAO 页没有提到 repository，也没有规定 DAO 与 repository 的层次关系（[DAOs](https://drift.simonbinder.eu/dart_api/daos/)，2026-11-24）。因此「DAO vs repository」不是 drift 官方的二选一；Flutter 官方要求 repository pattern，drift 只提供 DAO 作为查询模块化工具。

**stream query 的语义与代价。**

> `get()` "Runs the query once"；`watch()` "Watches the query, returning all rows"；所有 drift stream "will emit an up-to-date result after listening to them"。
> 更新机制："Whenever an insert, an update, or a deletion is made through drift APIs... the associated queries are rescheduled and will run again."
> 外部写入不触发："Other uses of the database, e.g. a native SQLite client, will not trigger stream query updates."
> 更新粒度粗："Stream queries generally update more often than they have to, since we can't filter for updates on specific rows only."
> 适用规模："Stream queries should typically return relatively few rows and not be too computationally expensive to execute."

（[Stream queries · Basics / Caveats](https://drift.simonbinder.eu/dart_api/streams/)，2026-11-24）

**transaction 的原子性与 stream 交互。**

> "Drift has support for transactions and allows multiple statements to run atomically." 事务完成前 "none of their changes is visible to the main database".
> 事务内所有 query 必须 `await`："All queries inside the transaction must be `await`-ed." 否则 "some queries might be operating on the transaction after it has been closed... This can cause data loss or runtime crashes."
> 事务外创建的 stream 只在事务提交后收到变更："All changes to tables will only be reported after the transaction completes."
> 事务内创建的 stream 会立即反映事务内变更，但 "such streams close when the transaction completes"，官方建议不要从事务外监听它。

（[Transactions · Transactions / Important things to know about transactions / Transactions and query streams](https://drift.simonbinder.eu/dart_api/transactions/)，2026-11-24）

**内存测试是官方推荐做法。**

> "This guide focuses on writing unit tests for a database written in drift." 测试可在电脑上跑，不需要设备。
> 用 `NativeDatabase.memory()` 创建内存数据库，在 `setUp` / `tearDown` 中打开与关闭。
> widget test 需要 `closeStreamsSynchronously: true`："In Flutter widget tests however, it's illegal to keep these timers open after a test concludes." 所以 "pass a `DatabaseConnection` with `closeStreamsSynchronously: true` to your database."

（[Testing · Setup / Writing tests / Closing streams synchronously](https://drift.simonbinder.eu/testing/)，2026-11-24）

### 1.4 Dart：sealed / pattern matching / immutability / lints

**sealed 用于「已知且可枚举的子类型集合」，并启用穷尽检查。**

> "To create a known, enumerable set of subtypes, use the `sealed` modifier."
> "The `sealed` modifier prevents a class from being extended or implemented outside its own library."
> "Sealed classes are implicitly `abstract`." "They cannot be constructed themselves."
> "Subclasses of sealed classes are, however, not implicitly abstract."
> sealed 使 switch "statically ensured to be exhaustive"；漏掉子类型会报 "The switch does not exhaustively account for all possible objects of type..."

（[Class modifiers · sealed / Exhaustiveness checking](https://dart.dev/language/class-modifiers)，2026-11-24）

**switch expression 与穷尽检查。** 官方 branches 页：

> "A switch expression produces a value based on the expression body of whichever case matches."
> "Exhaustiveness checking is a feature that reports a compile-time error" "if it's possible for a value to enter a switch but not match any of the cases."
> "Enums and sealed types are particularly useful for switches"; "even without a default case, their possible values are known and fully enumerable."
> "Use the `sealed` modifier on a class to enable exhaustiveness checking when switching over subtypes of that class."

（[Branches · Switch expressions / Exhaustiveness checking](https://dart.dev/language/branches)，2026-11-24）

**pattern 用于解构与 algebraic data type 风格。** 官方 patterns 页：

> "In general, a pattern can match a value, destructure a value, or both..."
> "Object destructuring and switch cases are conducive to writing code in an algebraic data type style."

（[Patterns · Matching / Destructuring / Algebraic data types](https://dart.dev/language/patterns)，2026-11-24）

**immutability 与 class modifier 的 Effective Dart 规则。**

> "PREFER making fields and top-level variables `final`" — "State that is not mutable... is easier for programmers to reason about." "if you don't need it, your default should be to make fields and top-level variables `final` when you can."
> "CONSIDER making your constructor `const` if the class supports it" — 但 const constructor 是 public API 承诺。
> "DO use class modifiers to control if your class can be extended" — "use these modifiers to communicate your intent, rather than relying on documentation."
> "AVOID defining custom equality for mutable classes."
> "PREFER making declarations private" — "Narrow public interfaces are easier for you to maintain and easier for users to learn."

（[Effective Dart: Design](https://dart.dev/effective-dart/design)，2026-11-24）

Flutter 官方也把 immutability 列为 **Strongly recommend**：

> "Use immutable data models." — "Immutable data is crucial in ensuring that any necessary changes occur only in the proper place... This process prevents accidental updates in the UI layer and supports a clear, unidirectional data flow."

（[Architecture recommendations · Handling data](https://docs.flutter.dev/app-architecture/recommendations)，2026-11-24）

**lints。** `flutter_lints` 提供 "Recommended lints for Flutter apps, packages, and plugins to encourage good coding practices"，并 "is built on top of Dart's `recommended.yaml` set of lints from package:lints"；通过 `include: package:flutter_lints/flutter.yaml` 启用（[flutter_lints](https://pub.dev/packages/flutter_lints)，2026-11-24）。这是 Flutter 官方包，不绑定某一种架构；官方没有要求额外 lint 集。

### 1.5 测试：金字塔、fakes、各层该测什么

**测试配比。** Flutter testing overview 没有使用「testing pyramid」一词，但给出等价结论：

> "Generally speaking, a well-tested app has many unit and widget tests, tracked by code coverage, plus enough integration tests to cover all the important use cases."

并给出取舍表：unit test 的 confidence 低、maintenance cost 低、dependencies 少、execution 快；widget test 居中；integration test 的 confidence 最高、maintenance cost 最高、dependencies 最多、execution 最慢（[Testing Flutter apps · Unit tests / Widget tests / Integration tests](https://docs.flutter.dev/testing/overview)，2026-11-24）。

**各层测什么。** 官方 recommendations 的 Testing 小节是 **Strongly recommend**：

> "Test architectural components separately, and together."
> "Write unit tests for every service, repository and ViewModel class. These tests should test the logic of every method individually."
> "Write widget tests for views. Testing routing and dependency injection are particularly important."
> "Make fakes for testing (and write code that takes advantage of fakes.)" — "Fakes aren't concerned with the inner workings of any given method as much as they're concerned with inputs and outputs."

（[Architecture recommendations · Testing](https://docs.flutter.dev/app-architecture/recommendations)，2026-11-24）

case study 的 testing 页把这条落到具体做法：

> "To test the UI logic of the view model, you should write unit tests that don't rely on Flutter libraries or testing frameworks."
> "Repositories are a view model's only dependencies (unless you're implementing use-cases), and writing `mocks` or `fakes` of the repository is the only setup you need to do."
> "The most important thing to take away is that view and view model tests only require mocking repositories if your architecture is sound."
> data layer："To write unit tests for any given repository, mock the services that it depends on."

（[Testing each layer · ViewModel unit tests / View widget tests / Testing the data layer](https://docs.flutter.dev/app-architecture/case-study/testing)，2026-11-24）

**fakes vs mocks。** Flutter 官方页没有给出二者的形式化定义；case study 同时使用 `FakeBookingRepository` / `FakeApiClient` 与 `mocktail` 的 `MockGoRouter`，并把「fake」作为首选推荐（[Testing each layer](https://docs.flutter.dev/app-architecture/case-study/testing)，2026-11-24）。Riverpod 官方则明确不鼓励 mock notifier，推荐 mock 它依赖的 repository / abstraction（[Testing your providers · Mocking Notifiers](https://riverpod.dev/docs/how_to/testing)，2026-11-24）。drift 官方推荐用真实内存数据库测 data layer（[Testing](https://drift.simonbinder.eu/testing/)，2026-11-24）。

**integration test 的官方定位。** overview 说它 "tests a complete app or a large part of an app"，目标是验证 widgets 与 services 一起工作，并可验证性能；通常跑在真机或模拟器上（[Testing Flutter apps · Integration tests](https://docs.flutter.dev/testing/overview)，2026-11-24）。专门的 integration test 页面只讲 `integration_test` 包的用法与各平台运行方式，**没有给出「何时该写 integration test」的一般决策标准，也没有成本讨论**（[Check app functionality with an integration test · Introduction](https://docs.flutter.dev/testing/integration-tests)，2026-11-24）。因此 integration 的数量只能按 overview 的「覆盖重要用例」来判断。

## 2. 来源列表

所有来源访问日期均为 **2026-11-24**。

| 来源 | 章节 | URL |
| --- | --- | --- |
| Guide to app architecture | Overview of project structure / MVVM / UI layer / Views / View models / Data layer / Repositories / Services / Optional: Domain layer / Data access with use-cases | https://docs.flutter.dev/app-architecture/guide |
| Common architecture concepts | Separation of concerns / Layered architecture | https://docs.flutter.dev/app-architecture/concepts |
| Architecture recommendations and resources | Separation of concerns / Handling data / App structure / Testing | https://docs.flutter.dev/app-architecture/recommendations |
| Architecture case study | Package structure / Other architecture options | https://docs.flutter.dev/app-architecture/case-study |
| Testing each layer (case study) | Testing the UI layer / ViewModel unit tests / View widget tests / Testing the data layer | https://docs.flutter.dev/app-architecture/case-study/testing |
| Communicating between layers (case study) | Dependency injection | https://docs.flutter.dev/app-architecture/case-study/dependency-injection |
| Testing Flutter apps | Unit tests / Widget tests / Integration tests | https://docs.flutter.dev/testing/overview |
| Check app functionality with an integration test | Introduction / Run integration tests | https://docs.flutter.dev/testing/integration-tests |
| Approaches to state management | 页面正文（无小节标题） | https://docs.flutter.dev/data-and-backend/state-mgmt/options |
| Riverpod: Providers | What is a provider? / Creating a provider | https://riverpod.dev/docs/concepts2/providers |
| Riverpod: Automatic disposal | Automatic disposal / When is automatic disposal triggered? / Fine-tuned disposal with ref.keepAlive | https://riverpod.dev/docs/concepts2/auto_dispose |
| Riverpod: Family | Family / Creating a Family / Using a Family | https://riverpod.dev/docs/concepts2/family |
| Riverpod: Scoping providers | Defining a scoped provider / Listening to a scoped provider / Dependency sharing | https://riverpod.dev/docs/concepts2/scoping |
| Riverpod: Testing your providers | Setting up a test / Mocking providers / Mocking Notifiers | https://riverpod.dev/docs/how_to/testing |
| Riverpod: About code generation | Should I use code generation? / The Syntax | https://riverpod.dev/docs/concepts/about_code_generation |
| Riverpod: DO/DON'T | DO/DON'T | https://riverpod.dev/docs/root/do_dont |
| Riverpod: What's new in 3.0 | Automatic retry / Pause/Resume support / Provider life-cycle changes / New testing utilities / Mutations (experimental) / Offline persistence (experimental) | https://riverpod.dev/docs/whats_new |
| drift: Stream queries | Basics / Caveats | https://drift.simonbinder.eu/dart_api/streams/ |
| drift: DAOs | DAOs | https://drift.simonbinder.eu/dart_api/daos/ |
| drift: Transactions | Transactions / Important things to know about transactions / Transactions and query streams | https://drift.simonbinder.eu/dart_api/transactions/ |
| drift: Testing | Setup / Writing tests / Closing streams synchronously | https://drift.simonbinder.eu/testing/ |
| Dart: Class modifiers | sealed / final / Exhaustiveness checking | https://dart.dev/language/class-modifiers |
| Dart: Branches | Switch expressions / Exhaustiveness checking | https://dart.dev/language/branches |
| Dart: Patterns | Matching / Destructuring / Algebraic data types | https://dart.dev/language/patterns |
| Effective Dart: Design | PREFER making fields and top-level variables final / CONSIDER making your constructor const / DO use class modifiers / AVOID defining custom equality for mutable classes / PREFER making declarations private | https://dart.dev/effective-dart/design |
| flutter_lints (pub.dev) | 包说明与推荐配置 | https://pub.dev/packages/flutter_lints |
