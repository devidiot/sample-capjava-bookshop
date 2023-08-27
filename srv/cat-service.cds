using my.bookshop as my from '../db/data-model';

service CatalogService @(path: '/browse') {
    @readonly entity Books as projection on my.Books;
}

service AdminService @(path: '/admin', requires: 'admin'){
    @readonly entity Books as projection on my.Books;
}