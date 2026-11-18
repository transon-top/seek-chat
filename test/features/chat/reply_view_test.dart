import 'package:flutter_test/flutter_test.dart';
import 'package:open_chat/features/chat/reply_view.dart';
import 'package:open_chat/shared/models/types.dart';

const _toolUse = 'toolu_1';

AssistantMessage _reply(
  List<ReplyBlock> blocks, {
  ReplyStatus status = ReplyStatus.done,
  StopReason stopReason = StopReason.endTurn,
  bool thinking = true,
  bool search = true,
}) =>
    AssistantMessage(
      id: 'reply',
      createdAt: DateTime(2026),
      status: status,
      blocks: blocks,
      stopReason: stopReason,
      thinking: thinking,
      search: search,
    );

ServerToolUseBlock _searchUse(
  String id,
  ServerToolKind kind,
  List<String> queries,
) =>
    ServerToolUseBlock(
      id: id,
      name: 'deepseek_web_search',
      input: SearchInput(queries: queries),
      kind: kind,
    );

WebSearchToolResultBlock _searchResult(
  String toolUseId,
  ServerToolKind kind,
  List<WebSearchResult> results,
) =>
    WebSearchToolResultBlock(
      toolUseId: toolUseId,
      kind: kind,
      content: results,
    );

WebSearchResult _result(
  String url, {
  String? title,
  String snippet = '',
  String? siteName,
  String? siteIcon,
  String? pageAge,
}) =>
    WebSearchResult(
      title: title ?? url,
      url: url,
      snippet: snippet,
      siteName: siteName,
      siteIcon: siteIcon,
      encryptedContent: '',
      pageAge: pageAge,
    );

ServerToolUseBlock _openUse(String id, String url) => ServerToolUseBlock(
      id: id,
      name: 'deepseek_web_search',
      input: OpenPageInput(url),
      kind: ServerToolKind.deepSearch,
    );

WebFetchToolResultBlock _fetchResult(
  String toolUseId,
  String url, {
  String? title,
  String? publishedAt,
  ServerToolKind kind = ServerToolKind.deepSearch,
}) =>
    WebFetchToolResultBlock(
      toolUseId: toolUseId,
      kind: kind,
      content: WebFetchResult(
        url: url,
        content: {'title': ?title},
        publishedAt: publishedAt,
      ),
    );

ServerToolUseBlock _findUse(String id, String url, String pattern) =>
    ServerToolUseBlock(
      id: id,
      name: 'deepseek_web_search',
      input: FindInPageInput(url: url, pattern: pattern),
      kind: ServerToolKind.deepSearch,
    );

ServerToolUseBlock _readUse(String id, String url) => ServerToolUseBlock(
      id: id,
      name: 'deepseek_read_url',
      input: ReadLinkInput(url),
      kind: ServerToolKind.readLink,
    );

const _citation = TextCitation(
  url: 'https://cite.example',
  title: 'Cited page',
  citedText: 'quoted',
  encryptedIndex: 'enc',
);

void main() {
  test('merges normal searches into their first position across a thinking block',
      () {
    final view = buildReplyView(
      _reply([
        _searchUse('s1', ServerToolKind.search, ['first']),
        _searchResult('s1', ServerToolKind.search, [
          _result('https://a.example', title: 'A'),
          _result('https://b.example', title: 'B'),
        ]),
        const ThinkingBlock(thinking: 'hmm'),
        _searchUse('s2', ServerToolKind.search, ['second']),
        _searchResult('s2', ServerToolKind.search, [
          _result('https://c.example', title: 'C'),
        ]),
        const TextBlock(text: 'answer'),
      ]),
      streaming: false,
    );

    expect(view.steps, hasLength(2));
    final search = view.steps.first as SearchStep;
    expect(search.queries, ['first', 'second']);
    expect(search.results.map((source) => source.title), ['A', 'B', 'C']);
    expect(view.steps.last, isA<ThinkingStep>());
    expect(view.answer?.markdown, 'answer');
    expect(view.searchResults, hasLength(3));
  });

  test('only merges adjacent deep searches', () {
    final view = buildReplyView(
      _reply([
        _searchUse('d1', ServerToolKind.deepSearch, ['one']),
        _searchResult('d1', ServerToolKind.deepSearch, [
          _result('https://one.example'),
        ]),
        const ThinkingBlock(thinking: 'pause'),
        _searchUse('d2', ServerToolKind.deepSearch, ['two']),
        _searchResult('d2', ServerToolKind.deepSearch, [
          _result('https://two.example'),
        ]),
        _searchUse('d3', ServerToolKind.deepSearch, ['three']),
        _searchResult('d3', ServerToolKind.deepSearch, [
          _result('https://three.example'),
        ]),
      ]),
      streaming: false,
    );

    final searches = view.steps.whereType<SearchStep>().toList();
    expect(searches, hasLength(2));
    expect(searches.first.queries, ['one']);
    expect(searches.last.queries, ['two', 'three']);
    expect(searches.last.results, hasLength(2));
  });

  test('merges tool status: any wip stays wip, all failed becomes failed', () {
    final wip = buildReplyView(
      _reply([
        _searchUse('s1', ServerToolKind.search, ['one']),
        _searchUse('s2', ServerToolKind.search, ['two']),
        _searchResult('s2', ServerToolKind.search, [
          _result('https://a.example'),
        ]),
      ], status: ReplyStatus.streaming),
      streaming: true,
    );
    expect((wip.steps.single as SearchStep).status, ToolStatus.wip);

    final failed = buildReplyView(
      _reply([
        _searchUse('s1', ServerToolKind.search, ['one']),
        _searchUse('s2', ServerToolKind.search, ['two']),
      ]),
      streaming: false,
    );
    expect((failed.steps.single as SearchStep).status, ToolStatus.failed);
  });

  test('shows read_link only while it is in progress', () {
    final blocks = <ReplyBlock>[
      _readUse(_toolUse, 'https://read.example'),
    ];

    final inProgress = buildReplyView(
      _reply(blocks, status: ReplyStatus.streaming),
      streaming: true,
    );
    final reading = inProgress.steps.single as ReadLinkStep;
    expect(reading.links.single.title, 'https://read.example');

    final done = buildReplyView(
      _reply([
        ...blocks,
        _fetchResult(
          _toolUse,
          'https://read.example',
          title: 'Read page',
          kind: ServerToolKind.readLink,
        ),
      ]),
      streaming: false,
    );
    expect(done.steps.whereType<ReadLinkStep>(), isEmpty);
  });

  test('hides read_link without any url or fetched page', () {
    final view = buildReplyView(
      _reply([
        _readUse(_toolUse, ''),
      ], status: ReplyStatus.streaming),
      streaming: true,
    );

    expect(view.steps, isEmpty);
  });

  test('merges adjacent page calls and keeps every page', () {
    final view = buildReplyView(
      _reply([
        for (var i = 0; i < 6; i++) _openUse('o$i', 'https://p$i.example'),
        _findUse('f1', 'https://p0.example', 'alpha'),
        _findUse('f2', 'https://p1.example', 'beta'),
      ]),
      streaming: false,
    );

    final open = view.steps.whereType<OpenStep>().single;
    expect(open.pages, hasLength(6));
    final find = view.steps.whereType<FindStep>().single;
    expect(find.patterns.map((item) => item.pattern), ['alpha', 'beta']);
  });

  test('deep search fetch results register a source without a search step', () {
    final view = buildReplyView(
      _reply([
        _openUse('o1', 'https://deep.example'),
        _fetchResult(
          'o1',
          'https://deep.example',
          title: 'Deep page',
          publishedAt: '2026-01-02',
        ),
        const TextBlock(text: 'answer'),
      ]),
      streaming: false,
    );

    expect(view.steps.whereType<SearchStep>(), isEmpty);
    expect(view.sources.single.title, 'Deep page');
    expect(view.sources.single.publishedAt, '2026-01-02');
    expect(view.searchResults, isEmpty);
  });

  test('registers each url once and only fills empty metadata', () {
    final view = buildReplyView(
      _reply([
        _searchUse('s1', ServerToolKind.search, ['one']),
        _searchResult('s1', ServerToolKind.search, [
          _result(
            'https://a.example',
            title: 'First title',
            snippet: 'first snippet',
            siteName: 'Site A',
          ),
        ]),
        const TextBlock(text: 'answer', citations: [_citation]),
        _searchUse('s2', ServerToolKind.search, ['two']),
        _searchResult('s2', ServerToolKind.search, [
          WebSearchResult(
            title: 'Better title',
            url: 'https://a.example',
            snippet: 'later snippet',
            siteName: 'Late site',
            siteIcon: 'https://a.example/icon.png',
            encryptedContent: '',
            pageAge: '2026-01-03',
          ),
        ]),
      ]),
      streaming: false,
    );

    expect(view.sources, hasLength(2));
    final source = view.sources.first;
    expect(source.index, 1);
    expect(source.title, 'First title');
    expect(source.snippet, 'first snippet');
    expect(source.siteName, 'Site A');
    expect(source.publishedAt, '2026-01-03');
    expect(source.siteIcon, 'https://a.example/icon.png');
    expect(view.sources.last.url, 'https://cite.example');
    expect(view.answer, isNull);
    expect(
      view.steps.whereType<PreambleStep>().single.markdown,
      'answer[citation:2]',
    );
  });

  test('numbers search results before body citations even when they appear later',
      () {
    final view = buildReplyView(
      _reply([
        const TextBlock(text: 'cited'),
        _searchUse('s1', ServerToolKind.search, ['one']),
        _searchResult('s1', ServerToolKind.search, [
          _result('https://found.example', title: 'Found'),
        ]),
      ]),
      streaming: false,
    );

    expect(view.sources.first.url, 'https://found.example');
    expect(view.sources.first.index, 1);
  });

  test('inserts citations before trailing whitespace and dedupes by url', () {
    const citation = TextCitation(
      url: 'https://cite.example',
      title: null,
      citedText: '',
      encryptedIndex: 'a',
    );
    const duplicate = TextCitation(
      url: 'https://cite.example',
      title: null,
      citedText: '',
      encryptedIndex: 'b',
    );
    final view = buildReplyView(
      _reply([
        const TextBlock(
          text: 'hello  \n',
          citations: [citation, duplicate],
        ),
      ]),
      streaming: false,
    );

    expect(view.answer?.markdown, 'hello[citation:1]  \n');
    expect(view.answer?.text, 'hello  \n');
  });

  test('falls back to the url and domain when metadata is missing', () {
    final view = buildReplyView(
      _reply([
        _searchUse('s1', ServerToolKind.search, ['one']),
        _searchResult('s1', ServerToolKind.search, [
          WebSearchResult(
            title: '',
            url: 'https://www.example.com/page',
            snippet: '',
            encryptedContent: '',
          ),
        ]),
      ]),
      streaming: false,
    );

    final source = view.sources.single;
    expect(source.title, 'https://www.example.com/page');
    expect(source.siteName, 'example.com');
    expect(source.snippet, isNull);
    expect(source.siteIcon, isNull);
  });

  test('keeps text before tools as a preamble and drops empty ones', () {
    final view = buildReplyView(
      _reply([
        const TextBlock(text: 'intro'),
        _searchUse('s1', ServerToolKind.search, ['one']),
        _searchResult('s1', ServerToolKind.search, [
          _result('https://a.example'),
        ]),
        const TextBlock(text: '   '),
        const TextBlock(text: 'answer'),
        const TextBlock(text: 'template', isTemplate: true),
      ]),
      streaming: false,
    );

    expect(view.steps.first, isA<PreambleStep>());
    expect((view.steps.first as PreambleStep).markdown, 'intro');
    expect(view.answer?.markdown, '   answer');
  });

  test('settles pending text before an empty thinking block', () {
    final view = buildReplyView(
      _reply([
        const TextBlock(text: 'intro'),
        const ThinkingBlock(thinking: ''),
        const TextBlock(text: 'answer'),
      ]),
      streaming: false,
    );

    expect(view.steps.single, isA<PreambleStep>());
    expect((view.steps.single as PreambleStep).markdown, 'intro');
    expect(view.answer?.markdown, 'answer');
  });

  test('a template text block breaks adjacent thinking blocks', () {
    final view = buildReplyView(
      _reply([
        const ThinkingBlock(thinking: 'one'),
        const TextBlock(text: 'template', isTemplate: true),
        const ThinkingBlock(thinking: 'two'),
      ]),
      streaming: false,
    );

    expect(view.steps.whereType<ThinkingStep>(), hasLength(2));
  });

  test('marks a search without results done when it returned an empty list', () {
    final view = buildReplyView(
      _reply([
        _searchUse('s1', ServerToolKind.search, ['one']),
        _searchResult('s1', ServerToolKind.search, const []),
      ]),
      streaming: false,
    );

    expect((view.steps.single as SearchStep).status, ToolStatus.done);
  });

  test('marks an unanswered search failed once the stream ends', () {
    final view = buildReplyView(
      _reply([
        _searchUse('s1', ServerToolKind.search, ['one']),
      ]),
      streaming: false,
    );

    expect((view.steps.single as SearchStep).status, ToolStatus.failed);
  });

  test('marks a search failed when the result carries an error', () {
    final view = buildReplyView(
      _reply([
        _searchUse('s1', ServerToolKind.search, ['one']),
        WebSearchToolResultBlock(
          toolUseId: 's1',
          kind: ServerToolKind.search,
          content: const [WebSearchResultError('unavailable')],
        ),
      ]),
      streaming: false,
    );

    expect((view.steps.single as SearchStep).status, ToolStatus.failed);
  });
}
